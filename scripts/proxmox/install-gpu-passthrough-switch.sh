#!/usr/bin/env bash
set -Eeuo pipefail

vmid=''
desktop_user=${SUDO_USER:-}
gpu_pci='0000:01:00.0'
audio_pci='0000:01:00.1'
shutdown_timeout=180
manage_display_manager=true
start_vm_after_resume=true

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/proxmox/install-gpu-passthrough-switch.sh --vmid ID [options]

Required:
  --vmid ID                 Windows 11 Proxmox VM ID

Options:
  --user NAME               Qtile desktop user (defaults to SUDO_USER)
  --gpu-pci ADDRESS         NVIDIA VGA PCI address (default: 0000:01:00.0)
  --audio-pci ADDRESS       NVIDIA audio PCI address (default: 0000:01:00.1)
  --shutdown-timeout SEC    Graceful VM shutdown limit (default: 180)
  --no-display-manager      Do not restart the X11 login session while switching
  --no-start-after-resume   Leave the Windows VM stopped after host resume
  -h, --help                Show this help

This installer does not add IOMMU kernel parameters, install NVIDIA drivers,
edit the VM configuration, or force-stop a guest.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

normalise_pci() {
    local address=$1
    [[ $address == 0000:* ]] || address="0000:$address"
    printf '%s\n' "${address,,}"
}

while (($#)); do
    case "$1" in
        --vmid) [[ $# -ge 2 ]] || die '--vmid requires a value.'; vmid=$2; shift ;;
        --user) [[ $# -ge 2 ]] || die '--user requires a value.'; desktop_user=$2; shift ;;
        --gpu-pci) [[ $# -ge 2 ]] || die '--gpu-pci requires a value.'; gpu_pci=$(normalise_pci "$2"); shift ;;
        --audio-pci) [[ $# -ge 2 ]] || die '--audio-pci requires a value.'; audio_pci=$(normalise_pci "$2"); shift ;;
        --shutdown-timeout) [[ $# -ge 2 ]] || die '--shutdown-timeout requires a value.'; shutdown_timeout=$2; shift ;;
        --no-display-manager) manage_display_manager=false ;;
        --no-start-after-resume) start_vm_after_resume=false ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID == 0)) || die 'Run this installer with sudo.'
[[ $vmid =~ ^[1-9][0-9]*$ ]] || die 'Provide a numeric VM ID with --vmid.'
[[ $desktop_user =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || die 'Could not determine a valid desktop user; use --user.'
[[ $gpu_pci =~ ^0000:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || die 'Invalid --gpu-pci address.'
[[ $audio_pci =~ ^0000:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || die 'Invalid --audio-pci address.'
[[ $shutdown_timeout =~ ^[1-9][0-9]*$ ]] || die 'The shutdown timeout must be a positive integer.'

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
unit_dir="$script_dir/systemd"

for command_name in qm systemctl modinfo lspci install visudo getent; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
done

getent passwd "$desktop_user" >/dev/null || die "Desktop user does not exist: $desktop_user"
qm status "$vmid" >/dev/null 2>&1 || die "Proxmox VM $vmid does not exist."

for pci in "$gpu_pci" "$audio_pci"; do
    [[ -d /sys/bus/pci/devices/$pci ]] || die "PCI device is not present: $pci"
done

[[ $(<"/sys/bus/pci/devices/$gpu_pci/vendor") == 0x10de ]] || die "$gpu_pci is not an NVIDIA device."
[[ $(<"/sys/bus/pci/devices/$gpu_pci/class") == 0x03* ]] || die "$gpu_pci is not a display-class device."
modinfo nvidia >/dev/null 2>&1 || die 'The host NVIDIA kernel driver is not installed for the running kernel.'
modinfo vfio-pci >/dev/null 2>&1 || die 'The vfio-pci kernel module is unavailable.'

vm_config=$(qm config "$vmid")
gpu_slot=${gpu_pci#0000:}
gpu_slot=${gpu_slot%.*}
if ! grep -Eq "^hostpci[0-9]+:.*${gpu_slot}" <<<"$vm_config"; then
    warn "VM $vmid does not visibly reference PCI slot $gpu_slot. Verify hostpci or resource-mapping configuration."
fi
grep -q '^onboot: 1$' <<<"$vm_config" || warn "VM $vmid does not currently show 'onboot: 1'."

gpu_id=$(printf '%s:%s' "$(<"/sys/bus/pci/devices/$gpu_pci/vendor")" "$(<"/sys/bus/pci/devices/$gpu_pci/device")")
gpu_id=${gpu_id//0x/}
vfio_search_paths=(/proc/cmdline)
[[ -d /etc/modprobe.d ]] && vfio_search_paths+=(/etc/modprobe.d)
[[ -f /etc/initramfs-tools/modules ]] && vfio_search_paths+=(/etc/initramfs-tools/modules)
if ! grep -Rqs -- "$gpu_id" "${vfio_search_paths[@]}" 2>/dev/null; then
    warn "Could not confirm boot-time VFIO matching for $gpu_id. Verify the GPU binds to vfio-pci before the VM autostarts."
fi

install -m 0755 "$script_dir/gpu-passthrough-switch.sh" /usr/local/sbin/gpu-passthrough-switch
install -m 0755 "$script_dir/gpu-passthrough-request-toggle.sh" /usr/local/sbin/gpu-passthrough-request-toggle
install -m 0755 "$script_dir/gpu-passthrough-toggle.sh" /usr/local/bin/gpu-passthrough-toggle
install -m 0755 "$script_dir/steam-nvidia.sh" /usr/local/bin/steam-nvidia
install -m 0644 "$unit_dir/gpu-passthrough-toggle.service" /etc/systemd/system/gpu-passthrough-toggle.service
install -m 0644 "$unit_dir/gpu-passthrough-boot.service" /etc/systemd/system/gpu-passthrough-boot.service
install -m 0644 "$unit_dir/gpu-passthrough-guard.service" /etc/systemd/system/gpu-passthrough-guard.service
install -m 0644 "$unit_dir/gpu-passthrough-sleep.service" /etc/systemd/system/gpu-passthrough-sleep.service
install -d -m 0755 /etc/systemd/system/pve-guests.service.d
install -m 0644 "$unit_dir/pve-guests-gpu-passthrough.conf" \
    /etc/systemd/system/pve-guests.service.d/50-gpu-passthrough-switch.conf
install -d -m 0755 /etc/systemd/logind.conf.d
install -m 0644 "$script_dir/logind/80-gpu-passthrough-power-key.conf" \
    /etc/systemd/logind.conf.d/80-gpu-passthrough-power-key.conf

config_tmp=$(mktemp)
sudoers_tmp=$(mktemp)
trap 'rm -f "$config_tmp" "$sudoers_tmp"' EXIT

{
    printf '# Installed by install-gpu-passthrough-switch.sh\n'
    printf 'VMID=%q\n' "$vmid"
    printf 'DESKTOP_USER=%q\n' "$desktop_user"
    printf 'GPU_PCI=%q\n' "$gpu_pci"
    printf 'AUDIO_PCI=%q\n' "$audio_pci"
    printf 'SHUTDOWN_TIMEOUT=%q\n' "$shutdown_timeout"
    printf 'MANAGE_DISPLAY_MANAGER=%q\n' "$manage_display_manager"
    printf 'START_VM_AFTER_RESUME=%q\n' "$start_vm_after_resume"
} >"$config_tmp"
install -o root -g root -m 0600 "$config_tmp" /etc/gpu-passthrough-switch.conf

printf '%s ALL=(root) NOPASSWD: %s, %s\n' \
    "$desktop_user" \
    '/usr/local/sbin/gpu-passthrough-switch status --short' \
    '/usr/local/sbin/gpu-passthrough-request-toggle' >"$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null
install -o root -g root -m 0440 "$sudoers_tmp" /etc/sudoers.d/gpu-passthrough-switch

systemctl daemon-reload
systemctl enable --now gpu-passthrough-guard.service
systemctl enable gpu-passthrough-boot.service
systemctl enable gpu-passthrough-sleep.service

printf '\n%s\n' 'GPU passthrough switch installed.'
printf 'Qtile user: %s\nVM ID: %s\nGPU: %s\nAudio: %s\n' \
    "$desktop_user" "$vmid" "$gpu_pci" "$audio_pci"
printf '%s\n' \
    'Reload the repository Qtile config, then use Super+Shift+G to toggle.' \
    'The first live switch should be done with no unsaved desktop work.' \
    'The power-button policy and boot recovery are fully active after the next reboot.' \
    'Check status with: sudo gpu-passthrough-switch status'
