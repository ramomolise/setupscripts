#!/usr/bin/env bash
set -u

section() {
    printf '\n## %s\n' "$1"
}

printf '# GPU passthrough report\nGenerated: %s\n' "$(date --iso-8601=seconds)"

section 'Kernel and command line'
uname -srmo
if [[ -r /proc/cmdline ]]; then
    cat /proc/cmdline
fi

section 'IOMMU status'
if compgen -G '/sys/kernel/iommu_groups/*' >/dev/null; then
    printf 'IOMMU groups detected: %s\n' "$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d | wc -l)"
else
    printf '%s\n' 'No IOMMU groups were found.'
fi

if [[ -d /sys/kernel/iommu_groups ]]; then
    while IFS= read -r device_path; do
        group=$(basename "$(dirname "$(dirname "$device_path")")")
        pci_id=$(basename "$device_path")
        description=$(lspci -nns "$pci_id" 2>/dev/null || true)
        case "$description" in
            *VGA*|*Audio*|*Display*|*3D*) printf 'Group %-4s %s\n' "$group" "$description" ;;
        esac
    done < <(find /sys/kernel/iommu_groups -type l -path '*/devices/*' | sort -V)
fi

section 'Display and audio PCI devices'
if command -v lspci >/dev/null 2>&1; then
    lspci -nnk | awk '
        /VGA compatible controller|3D controller|Display controller|Audio device/ { show=1; lines=0 }
        show { print; lines++ }
        show && lines >= 4 { show=0 }
    '
else
    printf '%s\n' 'lspci is not installed.'
fi

section 'VFIO modules'
if command -v lsmod >/dev/null 2>&1; then
    lsmod | awk 'NR == 1 || $1 ~ /^vfio/'
fi

section 'Kernel messages'
if dmesg_output=$(dmesg 2>/dev/null); then
    grep -Ei 'iommu|amd-vi|dmar|vfio' <<<"$dmesg_output" | tail -n 80 || true
else
    printf '%s\n' 'Kernel log is restricted; rerun with sudo for this section.'
fi

if command -v pveversion >/dev/null 2>&1; then
    section 'Proxmox VE'
    pveversion | head -n1
    printf '%s\n' 'VM configurations are intentionally not included.'
fi

printf '\nThis report makes no changes. Review it before sharing publicly.\n'
