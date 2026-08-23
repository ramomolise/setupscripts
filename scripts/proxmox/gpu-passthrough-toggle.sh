#!/usr/bin/env bash
set -u

notify() {
    local urgency=$1 title=$2 message=$3
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message"
    else
        printf '%s: %s\n' "$title" "$message"
    fi
}

status=$(sudo -n /usr/local/sbin/gpu-passthrough-switch status --short 2>/dev/null) || {
    notify critical 'GPU switch unavailable' 'Run the installer first or check the restricted sudo rule.'
    exit 1
}

case "$status" in
    vm:*)
        action='Shut down Windows and reclaim RTX 3090'
        detail='This waits for a graceful VM shutdown, switches the GPU to Linux, and restarts the login session.'
        ;;
    host:*)
        action='Return RTX 3090 to Windows VM'
        detail='Close Steam and every game first. Your login session will restart and the Windows VM will start.'
        ;;
    switching-*|error:*)
        notify normal 'GPU switch' "Current state: $status"
        exit 0
        ;;
    *)
        notify critical 'GPU state is unsafe' "Refusing to toggle from: $status"
        exit 1
        ;;
esac

if command -v rofi >/dev/null 2>&1; then
    choice=$(printf '%s\n%s\n' "$action" 'Cancel' | rofi -dmenu -i -p 'GPU mode')
    [[ $choice == "$action" ]] || exit 0
else
    notify critical 'GPU switch unavailable' 'Rofi is required for confirmation.'
    exit 1
fi

notify normal 'GPU switch starting' "$detail"
sudo -n /usr/local/sbin/gpu-passthrough-request-toggle || {
    notify critical 'GPU switch failed to start' 'Check: systemctl status gpu-passthrough-toggle.service'
    exit 1
}

# This monitor normally disappears when the display manager restarts. If the
# operation fails before that point, it reports the root-owned error file.
(
    switching_seen=false
    for ((attempt = 0; attempt < 240; attempt++)); do
        state=$(cat /run/gpu-passthrough-switch.state 2>/dev/null || true)
        case "$state" in
            switching-*) switching_seen=true ;;
            error)
                error_message=$(cat /run/gpu-passthrough-switch.last-error 2>/dev/null || true)
                notify critical 'GPU switch failed' "${error_message:-Inspect gpu-passthrough-toggle.service.}"
                exit 1
                ;;
            host|vm)
                if $switching_seen; then
                    notify normal 'GPU switch complete' "New mode: $state"
                    exit 0
                fi
                ;;
        esac
        sleep 1
    done
) &
