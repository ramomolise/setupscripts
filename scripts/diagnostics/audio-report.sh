#!/usr/bin/env bash
set -u

printf '%s\n' '## ALSA cards'
if [[ -r /proc/asound/cards ]]; then
    cat /proc/asound/cards
else
    printf '%s\n' '/proc/asound/cards is unavailable.'
fi

if ! command -v pactl >/dev/null 2>&1; then
    printf '%s\n' 'pactl is not installed or PipeWire/PulseAudio is unavailable.' >&2
    exit 1
fi

printf '%s\n' '' '## PipeWire/PulseAudio cards'
pactl list short cards || true

printf '%s\n' '' '## Available outputs'
pactl list short sinks || true

printf '%s\n' '' '## Current default output'
pactl get-default-sink || true

printf '%s\n' '' '## Output ports and active state'
pactl list sinks | awk '
    /Name:|Description:|Mute:|Active Port:|analog-output-headphones|analog-output-lineout/ { print }
'

printf '%s\n' '' '## Active audio services'
systemctl --user --no-pager --plain status pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null |
    sed -n '1,45p' || true
