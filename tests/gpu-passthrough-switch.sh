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
# shellcheck disable=SC2317
systemctl() { events+=("systemctl:$*"); }

switch_to_vm
assert_events $'state:switching-vm\nshutdown-vm\ncheck-workloads\nstop-display-manager\nstop-user-services\nstop-nvidia-services\ncheck-device-users\nbind-vfio\nstart-vm\nstart-display-manager\nstate:vm'

events=()
eval "$original_stop_nvidia_background_services"
stop_nvidia_background_services
assert_events $'systemctl:stop nvidia-persistenced.service nvidia-powerd.service'

events=()
vm_state() { printf '%s\n' stopped; }
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

grep -Fq -- '--close' "$script_dir/../scripts/proxmox/gpu-passthrough-switch.sh" || \
    fail 'Lock wrapper does not close the descriptor for the executed action.'
if grep -Eq 'exec[[:space:]]+9>' "$script_dir/../scripts/proxmox/gpu-passthrough-switch.sh"; then
    fail 'Legacy inherited FD-9 locking pattern is still present.'
fi

lock_test_dir=$(mktemp -d)
lock_test_pid=''
cleanup_lock_test() {
    if [[ -n $lock_test_pid ]]; then
        kill "$lock_test_pid" 2>/dev/null || true
        wait "$lock_test_pid" 2>/dev/null || true
    fi
    rm -rf "$lock_test_dir"
}
trap cleanup_lock_test EXIT

lock_test_helper="$lock_test_dir/lock-helper.sh"
cat >"$lock_test_helper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
source "$script_dir/../scripts/proxmox/gpu-passthrough-switch.sh"
load_config() { :; }
require_root() { :; }
cleanup() { :; }
die() {
    printf 'Error: %s\n' "\$*" >&2
    exit 1
}
execute_action() {
    if [[ -n \${GPU_SWITCH_LOCK_TEST_EXIT_CODE:-} ]]; then
        return "\$GPU_SWITCH_LOCK_TEST_EXIT_CODE"
    fi
    sleep 2 &
    child=\$!
    inherited=false
    for fd in /proc/\$child/fd/*; do
        [[ \$(readlink "\$fd" 2>/dev/null || true) == "\$LOCK_FILE" ]] && inherited=true
    done
    printf '%s\n' "\$inherited" >"\$GPU_SWITCH_LOCK_TEST_RESULT"
    : >"\$GPU_SWITCH_LOCK_TEST_READY"
    wait "\$child"
}
trap cleanup EXIT
main "\$@"
EOF
chmod +x "$lock_test_helper"

export GPU_SWITCH_LOCK_FILE="$lock_test_dir/switch.lock"
export GPU_SWITCH_LOCK_TEST_READY="$lock_test_dir/ready"
export GPU_SWITCH_LOCK_TEST_RESULT="$lock_test_dir/inherited"
"$lock_test_helper" vm >"$lock_test_dir/first.out" 2>"$lock_test_dir/first.err" &
lock_test_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -e $GPU_SWITCH_LOCK_TEST_READY ]] || break
    sleep 0.02
done
[[ -e $GPU_SWITCH_LOCK_TEST_READY ]] || fail 'Timed out waiting for locked child action.'
[[ $(cat "$GPU_SWITCH_LOCK_TEST_RESULT") == false ]] || \
    fail 'Child process inherited the GPU switch lock descriptor.'

if "$lock_test_helper" vm >"$lock_test_dir/second.out" 2>"$lock_test_dir/second.err"; then
    fail 'Concurrent GPU switch action was not refused.'
fi
grep -Fq 'Another GPU switch is already running.' "$lock_test_dir/second.err" || \
    fail 'Concurrent action did not report genuine lock contention.'
wait "$lock_test_pid" || fail 'Initial locked action failed.'
lock_test_pid=''

export GPU_SWITCH_LOCK_TEST_EXIT_CODE=42
set +e
"$lock_test_helper" vm >"$lock_test_dir/failure.out" 2>"$lock_test_dir/failure.err"
action_exit_code=$?
set -e
unset GPU_SWITCH_LOCK_TEST_EXIT_CODE
[[ $action_exit_code == 42 ]] || \
    fail "Action failure status changed from 42 to $action_exit_code."

trap - EXIT
cleanup_lock_test

printf '%s\n' 'GPU passthrough switch tests passed.'
