#!/usr/bin/env bash
set -Eeuo pipefail

base_url=${1:-http://127.0.0.1:11434}
base_url=${base_url%/}

command -v curl >/dev/null 2>&1 || {
    printf '%s\n' 'curl is required.' >&2
    exit 1
}

case "$base_url" in
    http://*|https://*) ;;
    *) printf '%s\n' 'Endpoint must begin with http:// or https://.' >&2; exit 2 ;;
esac

printf 'Checking Ollama endpoint: %s\n' "$base_url"

native_response=$(curl --fail --silent --show-error --max-time 10 "$base_url/api/tags")
openai_response=$(curl --fail --silent --show-error --max-time 10 "$base_url/v1/models")

if command -v jq >/dev/null 2>&1; then
    native_count=$(jq '.models | length' <<<"$native_response")
    openai_count=$(jq '.data | length' <<<"$openai_response")
    printf '  Native API models: %s\n' "$native_count"
    printf '  OpenAI API models: %s\n' "$openai_count"
    jq -r '.models[]?.name | "    - " + .' <<<"$native_response"
else
    printf '%s\n' '  Native /api/tags: reachable'
    printf '%s\n' '  OpenAI /v1/models: reachable'
fi

printf '%s\n' 'Ollama health check passed.'
