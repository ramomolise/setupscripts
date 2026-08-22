#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical 'NVIDIA GPU unavailable' 'Press Super+Shift+G to reclaim it from the Windows VM first.'
    fi
    exit 1
fi

exec env \
    __NV_PRIME_RENDER_OFFLOAD=1 \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __VK_LAYER_NV_optimus=NVIDIA_only \
    steam "$@"

