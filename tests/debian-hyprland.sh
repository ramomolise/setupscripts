#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile="$repo_root/setups/debian-hyprland"

grep -Fq 'hl.env("AQ_DRM_DEVICES", "/dev/dri/amd-igpu")' "$profile/config/hypr/source/environment.lua"
grep -Fq 'SUPER + SHIFT + G' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'gpu-passthrough-toggle' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.close()' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.float({ action = "toggle" })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.cycle_next()' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.focus({ direction = direction[2] })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.move({ direction = direction[2] })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.focus({ workspace = workspace })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.move({ workspace = workspace })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.focus({ workspace = "previous" })' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.drag()' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'hl.dsp.window.resize()' "$profile/config/hypr/source/keybinds.lua"
grep -Fq '{ mouse = true }' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'assert(not registered[keys], "duplicate keybinding: " .. keys)' "$profile/config/hypr/source/keybinds.lua"

if grep -Eq 'hyprctl dispatch (killactive|fullscreen|togglefloating|movefocus|movewindow|workspace|movetoworkspace)' "$profile/config/hypr/source/keybinds.lua"; then
    printf '%s\n' 'Legacy Hyprland dispatcher string found in core keybindings.' >&2
    exit 1
fi

python3 - "$profile/config/hypr/source/keybinds.lua" <<'PY'
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
shortcuts = re.findall(r'^(?:bind|command)\("([^"]+)"', source, re.MULTILINE)
shortcuts += [f"SUPER + {key}" for key in ("LEFT", "DOWN", "UP", "RIGHT", *"1234567890")]
shortcuts += [f"SUPER + SHIFT + {key}" for key in ("LEFT", "DOWN", "UP", "RIGHT", *"1234567890")]
duplicates = sorted({key for key in shortcuts if shortcuts.count(key) > 1})
if duplicates:
    raise SystemExit("duplicate/conflicting shortcuts: " + ", ".join(duplicates))
if "SUPER + L" in shortcuts:
    raise SystemExit("server profile must not bind Super+L")

required = {
    "SUPER + C", "SUPER + A", "SUPER + D", "ALT + TAB", "SUPER + TAB",
    "SUPER + mouse:272", "SUPER + mouse:273", "SUPER + Q", "SUPER + W",
    "SUPER + E", "ALT + SPACE", "CTRL + SHIFT + SPACE", "SUPER + SHIFT + G",
}
required.update(f"SUPER + {key}" for key in ("LEFT", "DOWN", "UP", "RIGHT", *"1234567890"))
required.update(f"SUPER + SHIFT + {key}" for key in ("LEFT", "DOWN", "UP", "RIGHT", *"1234567890"))
missing = sorted(required - set(shortcuts))
if missing:
    raise SystemExit("missing shortcuts: " + ", ".join(missing))
PY

if grep -Eq '^(bind|command)\("SUPER \+ L"' "$profile/config/hypr/source/keybinds.lua"; then
    printf '%s\n' 'Server profile must not bind Super+L.' >&2
    exit 1
fi

if grep -Rqi 'hyprlock' "$profile"; then
    printf '%s\n' 'Server profile contains a Hyprlock execution path.' >&2
    exit 1
fi

if grep -RqiE 'loginctl[[:space:]]+lock-session|lock-session|session_lock' "$profile"; then
    printf '%s\n' 'Server profile contains an automatic session-lock command.' >&2
    exit 1
fi

if grep -RqiE 'hypridle|systemctl[^[:cntrl:]]+(enable|start)[^[:cntrl:]]+[^[:space:]]*idle[^[:space:]]*\.service' "$profile"; then
    printf '%s\n' 'Server profile contains Hypridle autostart or an enabled idle service.' >&2
    exit 1
fi

grep -Fq 'BindsTo=graphical-session.target' "$profile/config/systemd/user/lan-mouse.service"
grep -Fq 'c43d211ec1af3eaea0cd585ac5c415776000355c3fcb9742fa2513f32dab55ba' "$profile/scripts/install-lan-mouse.sh"
grep -Fq 'Qtile remains installed' "$profile/install.sh"

if grep -Fq 'rgba(8455b8ff) rgba(c7c4ceff) 45deg' "$profile/config/hypr/source/appearance.lua"; then
    printf '%s\n' 'Unsupported Hyprland active-border gradient found.' >&2
    exit 1
fi

if grep -Eq '^[[:space:]]*pseudotile[[:space:]]*=' "$profile/config/hypr/source/appearance.lua"; then
    printf '%s\n' 'Unsupported Hyprland dwindle.pseudotile setting found.' >&2
    exit 1
fi

printf '%s\n' 'Debian Hyprland profile checks passed.'
