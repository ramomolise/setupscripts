#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_FILE=${GPU_SWITCH_CONFIG:-/etc/gpu-passthrough-switch.conf}
readonly LOCK_FILE=/run/lock/gpu-passthrough-switch.lock
readonly STATE_FILE=/run/gpu-passthrough-switch.state
readonly LAST_ERROR_FILE=/run/gpu-passthrough-switch.last-error
readonly SLEEP_DISPLAY_MARKER=/run/gpu-passthrough-switch.display-manager

display_manager_stopped=false
keep_display_manager_stopped=false

log() {
    printf '%s\n' "$*"
    logger -t gpu-passthrough-switch -- "$*" 2>/dev/null || true
}

die() {
    printf 'Error: %s\n' "$*" >&2
    if ((EUID == 0)); then
        printf '%s\n' "$*" >"$LAST_ERROR_FILE" || true
        chmod 0644 "$LAST_ERROR_FILE" 2>/dev/null || true
    fi
    exit 1
}

write_state() {
    local state=$1
    printf '%s\n' "$state" >"$STATE_FILE"
    chmod 0644 "$STATE_FILE"
}

cleanup() {
    local exit_code=$?

    if ((exit_code != 0)); then
        if ((EUID == 0)); then
            write_state error || true
        fi
        if $display_manager_stopped && ! $keep_display_manager_stopped; then
            systemctl start display-manager.service >/dev/null 2>&1 || true
        fi
    fi
}

load_config() {
    [[ -r "$CONFIG_FILE" ]] || die "Configuration not found: $CONFIG_FILE"
    VMID=''
    DESKTOP_USER=''
    GPU_PCI=''
    AUDIO_PCI=''
    SHUTDOWN_TIMEOUT=180
    MANAGE_DISPLAY_MANAGER=true
    START_VM_AFTER_RESUME=true
    # The installer creates this file as root with mode 0600.
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${VMID:?VMID is not set in $CONFIG_FILE}"
    : "${DESKTOP_USER:?DESKTOP_USER is not set in $CONFIG_FILE}"
    : "${GPU_PCI:?GPU_PCI is not set in $CONFIG_FILE}"
    : "${AUDIO_PCI:?AUDIO_PCI is not set in $CONFIG_FILE}"

    SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-180}
    MANAGE_DISPLAY_MANAGER=${MANAGE_DISPLAY_MANAGER:-true}
    START_VM_AFTER_RESUME=${START_VM_AFTER_RESUME:-true}

    [[ $VMID =~ ^[1-9][0-9]*$ ]] || die "Invalid VMID in $CONFIG_FILE"
    [[ $SHUTDOWN_TIMEOUT =~ ^[1-9][0-9]*$ ]] || die "Invalid SHUTDOWN_TIMEOUT in $CONFIG_FILE"
    [[ $GPU_PCI =~ ^0000:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || die "Invalid GPU_PCI in $CONFIG_FILE"
    [[ $AUDIO_PCI =~ ^0000:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || die "Invalid AUDIO_PCI in $CONFIG_FILE"
    [[ $MANAGE_DISPLAY_MANAGER == true || $MANAGE_DISPLAY_MANAGER == false ]] || die "MANAGE_DISPLAY_MANAGER must be true or false"
    [[ $START_VM_AFTER_RESUME == true || $START_VM_AFTER_RESUME == false ]] || die "START_VM_AFTER_RESUME must be true or false"
}

require_root() {
    ((EUID == 0)) || die 'This command must run as root.'
}

device_path() {
    printf '/sys/bus/pci/devices/%s\n' "$1"
}

current_driver() {
    local path
    path=$(device_path "$1")
    if [[ -L $path/driver ]]; then
        basename "$(readlink -f "$path/driver")"
    else
        printf '%s\n' unbound
    fi
}

vm_state() {
    local state
    state=$(qm status "$VMID" 2>/dev/null | awk '$1 == "status:" { print $2 }') || true
    printf '%s\n' "${state:-unknown}"
}

shutdown_vm() {
    local state deadline
    state=$(vm_state)
    [[ $state != unknown ]] || die "Cannot read the state of VM $VMID."
    [[ $state == stopped ]] && return 0

    log "Requesting a graceful shutdown of VM $VMID."
    if ! qm shutdown "$VMID" --timeout "$SHUTDOWN_TIMEOUT" --forceStop 0; then
        die "VM $VMID did not shut down cleanly; it was not force-stopped."
    fi

    deadline=$((SECONDS + SHUTDOWN_TIMEOUT))
    while [[ $(vm_state) != stopped ]]; do
        ((SECONDS < deadline)) || die "VM $VMID did not stop within ${SHUTDOWN_TIMEOUT}s; it was not force-stopped."
        sleep 2
    done
}

start_vm() {
    local state
    state=$(vm_state)
    [[ $state != unknown ]] || die "Cannot read the state of VM $VMID."
    if [[ $state != running ]]; then
        log "Starting VM $VMID."
        qm start "$VMID"
    fi
    [[ $(vm_state) == running ]] || die "VM $VMID did not reach the running state."
}

unbind_device() {
    local pci=$1 path
    path=$(device_path "$pci")
    if [[ -L $path/driver ]]; then
        printf '%s' "$pci" >"$path/driver/unbind"
    fi
}

bind_device() {
    local pci=$1 target_driver=$2 path attempt
    path=$(device_path "$pci")
    [[ -d $path ]] || die "PCI device $pci is not present."

    if [[ $(current_driver "$pci") == "$target_driver" ]]; then
        return 0
    fi

    unbind_device "$pci"
    printf '%s' "$target_driver" >"$path/driver_override"
    modprobe "$target_driver"
    printf '%s' "$pci" >/sys/bus/pci/drivers_probe

    for ((attempt = 0; attempt < 20; attempt++)); do
        [[ $(current_driver "$pci") == "$target_driver" ]] && return 0
        sleep 0.25
    done
    die "PCI device $pci did not bind to $target_driver."
}

non_display_gpu_clients() {
    command -v nvidia-smi >/dev/null 2>&1 || return 0
    { nvidia-smi pmon -c 1 2>/dev/null || true; } | awk '
        $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
            process_name=$NF
            if (process_name !~ /^(Xorg|Xwayland|nvidia-persiste)$/) {
                print $2 ":" process_name
            }
        }
    ' | sort -u
}

assert_no_gpu_workloads() {
    local clients
    clients=$(non_display_gpu_clients)
    [[ -z $clients ]] || die "The NVIDIA GPU is still in use (${clients//$'\n'/, }). Close Steam, games, CUDA, and Ollama processes, then retry."
}

assert_no_device_users() {
    local nodes=() users
    command -v fuser >/dev/null 2>&1 || return 0

    shopt -s nullglob
    nodes=(/dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools)
    shopt -u nullglob
    ((${#nodes[@]} > 0)) || return 0

    if users=$(fuser "${nodes[@]}" 2>&1); then
        die "NVIDIA device files are still open after the desktop stopped: $users"
    fi
}

stop_display_manager() {
    $MANAGE_DISPLAY_MANAGER || return 0
    if systemctl is-active --quiet display-manager.service; then
        log 'Stopping the display manager so X11 releases the NVIDIA GPU.'
        systemctl stop display-manager.service
        display_manager_stopped=true
    fi
}

start_display_manager() {
    $MANAGE_DISPLAY_MANAGER || return 0
    if $display_manager_stopped; then
        systemctl start display-manager.service
        display_manager_stopped=false
    fi
}

stop_desktop_user_services() {
    local user_id
    user_id=$(id -u "$DESKTOP_USER" 2>/dev/null) || return 0
    systemctl stop "user@${user_id}.service" >/dev/null 2>&1 || true
}

stop_nvidia_background_services() {
    systemctl stop \
        nvidia-persistenced.service \
        nvidia-powerd.service >/dev/null 2>&1 || true
}

bind_to_host() {
    log "Binding $GPU_PCI to nvidia and $AUDIO_PCI to snd_hda_intel."
    bind_device "$GPU_PCI" nvidia
    bind_device "$AUDIO_PCI" snd_hda_intel
    modprobe nvidia_modeset
    modprobe nvidia_drm modeset=1
    modprobe nvidia_uvm
    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle || true
    fi
    if command -v nvidia-modprobe >/dev/null 2>&1; then
        nvidia-modprobe -u -c=0 || true
    fi
    command -v nvidia-smi >/dev/null 2>&1 || die 'nvidia-smi is not installed.'
    nvidia-smi >/dev/null || die 'The NVIDIA driver loaded, but nvidia-smi could not initialise the GPU.'
}

bind_to_vfio() {
    log "Binding $GPU_PCI and $AUDIO_PCI to vfio-pci."
    stop_nvidia_background_services

    if [[ $(current_driver "$GPU_PCI") == nvidia ]]; then
        modprobe -r nvidia_drm nvidia_uvm nvidia_modeset nvidia || \
            die 'The NVIDIA modules could not be unloaded. Check for remaining GPU clients.'
    fi

    bind_device "$GPU_PCI" vfio-pci
    bind_device "$AUDIO_PCI" vfio-pci
}

switch_to_host() {
    write_state switching-host
    shutdown_vm
    stop_display_manager
    bind_to_host
    start_display_manager
    write_state host
    log 'GPU mode is now host. Log in again and launch Steam with steam-nvidia.'
}

switch_to_vm() {
    write_state switching-vm
    shutdown_vm
    assert_no_gpu_workloads
    stop_display_manager
    stop_desktop_user_services
    stop_nvidia_background_services
    assert_no_device_users
    bind_to_vfio
    start_vm
    start_display_manager
    write_state vm
    log "GPU mode is now passthrough and VM $VMID is running."
}

prepare_sleep() {
    write_state switching-sleep
    shutdown_vm

    if systemctl is-active --quiet display-manager.service; then
        printf '%s\n' active >"$SLEEP_DISPLAY_MARKER"
    else
        printf '%s\n' inactive >"$SLEEP_DISPLAY_MARKER"
    fi

    stop_display_manager
    stop_desktop_user_services
    bind_to_vfio
    write_state vm-sleep
    log 'GPU is safely bound to VFIO for host sleep.'
}

prepare_boot() {
    local guest
    guest=$(vm_state)
    [[ $guest == stopped ]] || die "Boot recovery refused because VM $VMID is $guest."
    if systemctl is-active --quiet display-manager.service; then
        die 'Boot recovery refused because the display manager is already active.'
    fi

    write_state switching-boot
    bind_to_vfio
    write_state vm-boot
    log 'Boot recovery confirmed the GPU is bound to VFIO before guest autostart.'
}

resume_from_sleep() {
    local display_marker
    display_marker=$(cat "$SLEEP_DISPLAY_MARKER" 2>/dev/null || true)
    if [[ $display_marker == active ]]; then
        display_manager_stopped=true
    fi

    bind_to_vfio
    if $START_VM_AFTER_RESUME; then
        start_vm
    fi

    if [[ $display_marker == active ]]; then
        systemctl start display-manager.service
        display_manager_stopped=false
    fi
    rm -f "$SLEEP_DISPLAY_MARKER"
    write_state vm
    log 'Resume complete; GPU remains in passthrough mode.'
}

prepare_shutdown() {
    write_state switching-poweroff
    shutdown_vm
    stop_display_manager
    stop_desktop_user_services
    keep_display_manager_stopped=true
    bind_to_vfio
    write_state vm-poweroff
    log 'GPU is safely bound to VFIO for shutdown or reboot.'
}

print_status() {
    local gpu_driver audio_driver guest mode
    gpu_driver=$(current_driver "$GPU_PCI")
    audio_driver=$(current_driver "$AUDIO_PCI")
    guest=$(vm_state)

    case "$gpu_driver:$audio_driver" in
        vfio-pci:vfio-pci) mode=vm ;;
        nvidia:snd_hda_intel) mode=host ;;
        *) mode=mixed ;;
    esac

    if [[ ${1:-} == --short ]]; then
        printf '%s:%s\n' "$mode" "$guest"
    else
        printf 'Mode: %s\nGPU driver: %s\nAudio driver: %s\nVM %s: %s\n' \
            "$mode" "$gpu_driver" "$audio_driver" "$VMID" "$guest"
    fi
}

main() {
    local action=${1:-status}
    load_config
    require_root

    if [[ $action == status ]]; then
        print_status "${2:-}"
        return 0
    fi

    exec 9>"$LOCK_FILE"
    flock -n 9 || die 'Another GPU switch is already running.'
    rm -f "$LAST_ERROR_FILE"

    case "$action" in
        host) switch_to_host ;;
        vm) switch_to_vm ;;
        toggle)
            case "$(current_driver "$GPU_PCI")" in
                vfio-pci) switch_to_host ;;
                nvidia) switch_to_vm ;;
                *) die "GPU $GPU_PCI is not bound to vfio-pci or nvidia." ;;
            esac
            ;;
        prepare-sleep) prepare_sleep ;;
        resume) resume_from_sleep ;;
        prepare-boot) prepare_boot ;;
        prepare-shutdown) prepare_shutdown ;;
        *) die 'Usage: gpu-passthrough-switch {status [--short]|host|vm|toggle|prepare-boot|prepare-sleep|resume|prepare-shutdown}' ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    trap cleanup EXIT
    main "$@"
fi
