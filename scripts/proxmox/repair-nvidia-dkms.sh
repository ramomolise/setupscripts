#!/usr/bin/env bash
set -Eeuo pipefail

apply_changes=false
requested_version=''
readonly MODULES_ROOT=${NVIDIA_RECOVERY_MODULES_ROOT:-/lib/modules}

usage() {
    cat <<'EOF'
Usage: repair-nvidia-dkms.sh [--apply] [--module-version VERSION]

Diagnose whether the installed NVIDIA DKMS driver has a module for the running
Debian/Proxmox kernel. Diagnosis is the default and does not change the system.

Options:
  --apply                   Install exact running-kernel headers when missing,
                            rebuild the registered NVIDIA DKMS module, run
                            depmod, and refresh that kernel's initramfs
  --module-version VERSION  Select a registered NVIDIA DKMS version when more
                            than one version is present
  -h, --help                Show this help

This tool never purges or upgrades the NVIDIA driver, removes kernels, rebinds
PCI devices, changes VFIO/IOMMU configuration, or reboots the host.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

running_kernel() {
    uname -r
}

package_known() {
    local package=$1

    dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | \
        grep -Fxq 'install ok installed' && return 0
    apt-cache show "$package" 2>/dev/null | grep -Fq 'Package:'
}

resolve_header_package() {
    local kernel=$1 candidate
    local candidates=(
        "proxmox-headers-$kernel"
        "pve-headers-$kernel"
        "linux-headers-$kernel"
    )

    for candidate in "${candidates[@]}"; do
        if package_known "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

headers_present() {
    [[ -d $MODULES_ROOT/$1/build ]]
}

detect_nvidia_versions() {
    dkms status 2>/dev/null | sed -nE 's/^nvidia\/([^,]+),.*/\1/p' | sort -u
}

select_nvidia_version() {
    local requested=${1:-} version
    local versions=()
    mapfile -t versions < <(detect_nvidia_versions)

    ((${#versions[@]} > 0)) || \
        die 'No registered NVIDIA DKMS module was found. This tool will not install a new driver.'

    if [[ -n $requested ]]; then
        for version in "${versions[@]}"; do
            [[ $version == "$requested" ]] && {
                printf '%s\n' "$version"
                return 0
            }
        done
        die "NVIDIA DKMS version $requested is not registered."
    fi

    ((${#versions[@]} == 1)) || \
        die "Multiple NVIDIA DKMS versions are registered (${versions[*]}). Select one with --module-version."
    printf '%s\n' "${versions[0]}"
}

module_available() {
    modinfo -k "$1" nvidia >/dev/null 2>&1
}

dkms_installed_for_kernel() {
    dkms status -m nvidia -v "$1" -k "$2" 2>/dev/null | \
        grep -Eq ': installed$'
}

package_database_clean() {
    [[ -z $(dpkg --audit 2>/dev/null) ]]
}

install_header_package() {
    apt-get install --no-install-recommends "$1"
}

install_dkms_module() {
    local version=$1 kernel=$2 force=${3:-false}
    local arguments=(install -m nvidia -v "$version" -k "$kernel")
    $force && arguments+=(--force)
    dkms "${arguments[@]}"
}

refresh_module_metadata() {
    local kernel=$1
    depmod -a "$kernel"
    update-initramfs -u -k "$kernel"
}

print_module_details() {
    local kernel=$1
    printf 'NVIDIA module version: %s\n' \
        "$(modinfo -k "$kernel" -F version nvidia 2>/dev/null || printf unavailable)"
    printf 'NVIDIA module vermagic: %s\n' \
        "$(modinfo -k "$kernel" -F vermagic nvidia 2>/dev/null || printf unavailable)"
}

run_recovery() {
    local kernel header_package version
    local header_state=missing module_state=missing dkms_state=missing
    local package_state=attention

    kernel=$(running_kernel)
    header_package=$(resolve_header_package "$kernel" || printf unavailable)
    version=$(select_nvidia_version "$requested_version")

    headers_present "$kernel" && header_state=present
    module_available "$kernel" && module_state=present
    dkms_installed_for_kernel "$version" "$kernel" && dkms_state=installed
    package_database_clean && package_state=clean

    printf 'Mode: %s\n' "$($apply_changes && printf apply || printf diagnosis)"
    printf 'Running kernel: %s\n' "$kernel"
    printf 'Header package: %s\n' "$header_package"
    printf 'Header tree: %s\n' "$header_state"
    printf 'NVIDIA DKMS version: %s\n' "$version"
    printf 'DKMS status for running kernel: %s\n' "$dkms_state"
    printf 'NVIDIA module for running kernel: %s\n' "$module_state"
    printf 'Package database: %s\n' "$package_state"

    if [[ $module_state == present ]]; then
        print_module_details "$kernel"
        printf '%s\n' 'No repair is required.'
        return 0
    fi

    if ! $apply_changes; then
        printf '\n%s\n' 'Repair is required. Re-run as root with --apply after reviewing this report.'
        return 2
    fi

    [[ $package_state == clean ]] || \
        die 'dpkg reports unfinished package work. Resolve it before running this repair.'

    [[ $header_package != unavailable ]] || \
        die "No header package for running kernel $kernel is available from the configured APT sources. Refresh the package lists or correct the repositories, then retry."

    if [[ $header_state == missing ]]; then
        install_header_package "$header_package"
        headers_present "$kernel" || \
            die "The header tree for $kernel is still unavailable after installing $header_package."
    fi

    # Installing headers can invoke the distribution's DKMS post-install hook.
    # Re-check instead of trying to install an already-built module again.
    if ! module_available "$kernel"; then
        if dkms_installed_for_kernel "$version" "$kernel"; then
            warn 'DKMS reports the target installed but modinfo cannot find it; rebuilding with --force.'
            install_dkms_module "$version" "$kernel" true
        else
            install_dkms_module "$version" "$kernel" false
        fi
    fi

    refresh_module_metadata "$kernel"
    module_available "$kernel" || \
        die "NVIDIA DKMS completed but the nvidia module is still unavailable for $kernel."

    printf '\n%s\n' 'NVIDIA module recovery completed successfully.'
    print_module_details "$kernel"
    printf '%s\n' \
        'No GPU was rebound and no reboot was performed.' \
        'If a passthrough switch is installed, verify ownership before starting a guest.'
}

main() {
    while (($#)); do
        case "$1" in
            --apply) apply_changes=true ;;
            --module-version)
                [[ $# -ge 2 ]] || die '--module-version requires a value.'
                requested_version=$2
                shift
                ;;
            -h|--help) usage; return 0 ;;
            *) usage >&2; die "Unknown argument: $1" ;;
        esac
        shift
    done

    for command_name in uname dpkg dpkg-query apt-cache dkms modinfo sed sort grep; do
        require_command "$command_name"
    done

    if $apply_changes; then
        ((EUID == 0)) || die 'Run with sudo when using --apply.'
        for command_name in apt-get depmod update-initramfs; do
            require_command "$command_name"
        done
    fi

    run_recovery
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
