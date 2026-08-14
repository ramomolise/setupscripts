#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: custom-resolution.sh OUTPUT WIDTH HEIGHT [REFRESH]

Example:
  ./scripts/general/custom-resolution.sh HDMI-1 1920 1080 60

This changes the current X11 session only. It does not work on Wayland.
EOF
}

if [[ ${1:-} == '-h' || ${1:-} == '--help' ]]; then
    usage
    exit 0
fi

[[ $# -ge 3 && $# -le 4 ]] || {
    usage >&2
    exit 2
}

output=$1
width=$2
height=$3
refresh=${4:-60}

for value in "$width" "$height" "$refresh"; do
    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
        printf 'Invalid numeric value: %s\n' "$value" >&2
        exit 2
    }
done

command -v cvt >/dev/null 2>&1 || {
    printf '%s\n' 'Install the package that provides cvt first.' >&2
    exit 1
}
command -v xrandr >/dev/null 2>&1 || {
    printf '%s\n' 'xrandr is not installed.' >&2
    exit 1
}
[[ -n ${DISPLAY:-} ]] || {
    printf '%s\n' 'No X11 DISPLAY is available.' >&2
    exit 1
}
xrandr --query | grep -Eq "^${output}[[:space:]]+connected" || {
    printf 'Connected output not found: %s\n' "$output" >&2
    exit 1
}

modeline=$(cvt "$width" "$height" "$refresh" | awk '/Modeline/ { print; exit }')
[[ -n "$modeline" ]] || {
    printf '%s\n' 'cvt did not return a modeline.' >&2
    exit 1
}

mode_name=$(sed -n 's/.*Modeline "\([^"]*\)".*/\1/p' <<<"$modeline")
mode_parameters=${modeline#*\"}
mode_parameters=${mode_parameters#*\"}
read -r -a parameters <<<"$mode_parameters"

if ! xrandr --query | grep -Fq "$mode_name"; then
    xrandr --newmode "$mode_name" "${parameters[@]}"
fi

xrandr --addmode "$output" "$mode_name" 2>/dev/null || true
xrandr --output "$output" --mode "$mode_name"

printf 'Applied %s to %s for this X11 session.\n' "$mode_name" "$output"
