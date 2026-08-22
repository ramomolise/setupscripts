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
export SHUTDOWN_TIMEOUT=180

original_shutdown_vm=$(declare -f shutdown_vm)
events=()
log() { :; }
write_state() { events+=("state:$1"); }
shutdown_vm() { events+=(shutdown-vm); }
stop_display_manager() { events+=(stop-display-manager); }
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
assert_events $'state:switching-vm\nshutdown-vm\ncheck-workloads\nstop-display-manager\nsystemctl:stop nvidia-persistenced.service\ncheck-device-users\nbind-vfio\nstart-vm\nstart-display-manager\nstate:vm'

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

printf '%s\n' 'GPU passthrough switch tests passed.'
