#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/proxmox/gpu-passthrough-switch.sh
source "$script_dir/../scripts/proxmox/gpu-passthrough-switch.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_events() {
    local expected=$1 actual
    actual=$(printf '%s\n' "${events[@]}")
    [[ $actual == "$expected" ]] || fail "Unexpected sequence:\n$actual"
}

export VMID=101
export DESKTOP_USER=ramo
export SHUTDOWN_TIMEOUT=180

original_shutdown_vm=$(declare -f shutdown_vm)
original_stop_nvidia_background_services=$(declare -f stop_nvidia_background_services)
events=()
log() { :; }
write_state() { events+=("state:$1"); }
shutdown_vm() { events+=(shutdown-vm); }
stop_display_manager() { events+=(stop-display-manager); }
stop_desktop_user_services() { events+=(stop-user-services); }
stop_nvidia_background_services() { events+=(stop-nvidia-services); }
bind_to_host() { events+=(bind-host); }
start_display_manager() { events+=(start-display-manager); }

switch_to_host
assert_events $'state:switching-host\nshutdown-vm\nstop-display-manager\nbind-host\nstart-display-manager\nstate:host'

events=()
assert_no_gpu_workloads() { events+=(check-workloads); }
assert_no_device_users() { events+=(check-device-users); }
bind_to_vfio() { events+=(bind-vfio); }
start_vm() { events+=(start-vm); }
systemctl() { events+=("systemctl:$*"); }

switch_to_vm
assert_events $'state:switching-vm\nshutdown-vm\ncheck-workloads\nstop-display-manager\nstop-user-services\nstop-nvidia-services\ncheck-device-users\nbind-vfio\nstart-vm\nstart-display-manager\nstate:vm'

events=()
eval "$original_stop_nvidia_background_services"
stop_nvidia_background_services
assert_events $'systemctl:stop nvidia-persistenced.service nvidia-powerd.service'

events=()
vm_state() { printf '%s\n' stopped; }
# shellcheck disable=SC2317
systemctl() {
    [[ $1 == is-active ]] && return 1
    events+=("systemctl:$*")
}

prepare_boot
assert_events $'state:switching-boot\nbind-vfio\nstate:vm-boot'

mock_vm_state=running
qm_arguments=''
eval "$original_shutdown_vm"
vm_state() { printf '%s\n' "$mock_vm_state"; }
qm() {
    qm_arguments=$*
    mock_vm_state=stopped
}

shutdown_vm
[[ $qm_arguments == 'shutdown 101 --timeout 180 --forceStop 0' ]] || \
    fail "Graceful shutdown arguments changed: $qm_arguments"

condition_template="$script_dir/../scripts/proxmox/systemd/nvidia-gpu-passthrough.conf"
installer="$script_dir/../scripts/proxmox/install-gpu-passthrough-switch.sh"
grep -Fxq 'ConditionPathExists=!/etc/gpu-passthrough-switch.conf' "$condition_template" || \
    fail 'NVIDIA service condition template is missing.'
for unit in \
    nvidia-persistenced.service \
    nvidia-powerd.service \
    nvidia-suspend.service \
    nvidia-hibernate.service \
    nvidia-resume.service; do
    grep -Fq "$unit" "$installer" || fail "Installer does not list $unit."
done
grep -Fq "/etc/systemd/system/\${nvidia_unit}.d/50-gpu-passthrough-switch.conf" "$installer" || \
    fail 'Installer does not deploy NVIDIA condition drop-ins to the expected path.'
grep -Fq 'systemctl stop nvidia-persistenced.service nvidia-powerd.service' "$installer" || \
    fail 'Installer does not stop both NVIDIA background services.'

printf '%s\n' 'GPU passthrough switch tests passed.'
