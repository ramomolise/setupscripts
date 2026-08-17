#!/usr/bin/env bash
set -u

section() {
    printf '\n## %s\n' "$1"
}

run_if_available() {
    local command_name=$1
    shift
    if command -v "$command_name" >/dev/null 2>&1; then
        "$command_name" "$@" 2>&1 || true
    else
        printf '%s\n' "$command_name: not installed"
    fi
}

printf '# Linux system report\nGenerated: %s\n' "$(date --iso-8601=seconds)"

section 'Operating system'
if [[ -r /etc/os-release ]]; then
    awk -F= '/^(PRETTY_NAME|VERSION_ID)=/ { gsub(/"/, "", $2); print $1 ": " $2 }' /etc/os-release
fi
printf 'Kernel: %s\n' "$(uname -srmo)"
printf 'Session: %s / %s\n' "${XDG_SESSION_TYPE:-unknown}" "${XDG_CURRENT_DESKTOP:-unknown}"

section 'CPU and virtualization'
run_if_available lscpu | awk -F: '/^(Model name|Architecture|CPU\(s\)|Thread|Core|Virtualization):/ { gsub(/^[ \t]+/, "", $2); print $1 ": " $2 }'

section 'Memory'
run_if_available free -h

section 'Storage'
run_if_available lsblk -e 7 -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
run_if_available df -hT /

section 'Graphics controllers'
if command -v lspci >/dev/null 2>&1; then
    lspci -nnk | awk '
        /VGA compatible controller|3D controller|Display controller/ { show=1; lines=0 }
        show { print; lines++ }
        show && lines >= 4 { show=0 }
    '
else
    printf '%s\n' 'lspci: not installed'
fi

section 'Desktop processes'
for process_name in qtile picom dunst Xorg Hyprland waybar; do
    if pgrep -x "$process_name" >/dev/null 2>&1; then
        printf '%-12s running\n' "$process_name"
    else
        printf '%-12s stopped\n' "$process_name"
    fi
done

section 'AI toolchain'
for command_name in ollama hermes codex; do
    if command -v "$command_name" >/dev/null 2>&1; then
        printf '%-10s %s\n' "$command_name" "$("$command_name" --version 2>&1 | head -n1)"
    else
        printf '%-10s not installed\n' "$command_name"
    fi
done

if command -v pveversion >/dev/null 2>&1; then
    section 'Proxmox VE'
    pveversion -v 2>&1 || true
fi

section 'Failed systemd units'
run_if_available systemctl --failed --no-pager --plain

printf '\nReview this report before sharing it publicly.\n'
