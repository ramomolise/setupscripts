#!/usr/bin/env bash
set -Eeuo pipefail

if (($# != 0)); then
    printf '%s\n' 'This command does not accept arguments.' >&2
    exit 2
fi

if ((EUID != 0)); then
    printf '%s\n' 'This command must run through the installed sudo rule.' >&2
    exit 1
fi

systemctl start --no-block gpu-passthrough-toggle.service

