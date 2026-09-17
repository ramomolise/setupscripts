#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile="$repo_root/setups/debian-hyprland"

grep -Fq 'hl.env("AQ_DRM_DEVICES", "/dev/dri/amd-igpu")' "$profile/config/hypr/source/environment.lua"
grep -Fq 'SUPER + SHIFT + G' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'gpu-passthrough-toggle' "$profile/config/hypr/source/keybinds.lua"
grep -Fq 'BindsTo=graphical-session.target' "$profile/config/systemd/user/lan-mouse.service"
grep -Fq 'c43d211ec1af3eaea0cd585ac5c415776000355c3fcb9742fa2513f32dab55ba' "$profile/scripts/install-lan-mouse.sh"
grep -Fq 'Qtile remains installed' "$profile/install.sh"

printf '%s\n' 'Debian Hyprland profile checks passed.'
