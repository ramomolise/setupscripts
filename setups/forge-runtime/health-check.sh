#!/usr/bin/env bash
set -Eeuo pipefail

endpoint=${OLLAMA_HOST:-http://127.0.0.1:11434}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

check_command() {
    local command_name=$1
    if command -v "$command_name" >/dev/null 2>&1; then
        printf '%-10s %s\n' "$command_name" "$("$command_name" --version 2>&1 | head -n1)"
    else
        printf '%-10s %s\n' "$command_name" 'not installed'
    fi
}

printf '%s\n' 'Forge toolchain'
check_command codex
check_command hermes
check_command ollama
check_command git
check_command jq

printf '%s\n' '' 'Ollama endpoint'
"$repo_root/scripts/ollama/health-check.sh" "$endpoint"

if command -v ollama >/dev/null 2>&1; then
    printf '%s\n' '' 'Loaded Ollama models'
    ollama ps || true
fi
