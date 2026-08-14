#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    printf '%s\n' 'Run this check inside the repository.' >&2
    exit 2
}

cd "$repo_root"

patterns=(
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'AIza[0-9A-Za-z_-]{30,}'
    'gh[pousr]_[0-9A-Za-z]{20,}'
    'sk-[0-9A-Za-z]{20,}'
    "(api[_-]?key|access[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*[\"']?[0-9A-Za-z_./+=-]{16,}"
)

status=0
for pattern in "${patterns[@]}"; do
    mapfile -t matches < <(
        git grep --untracked --exclude-standard -IlE -e "$pattern" -- . \
            ':(exclude)scripts/check-secrets.sh' \
            ':(exclude)SECURITY.md' || true
    )
    if ((${#matches[@]})); then
        status=1
        printf '%s\n' 'Possible secret pattern found in:' >&2
        printf '  %s\n' "${matches[@]}" >&2
    fi
done

if ((status)); then
    printf '%s\n' 'Secret scan failed. Values were intentionally not printed.' >&2
    exit 1
fi

printf '%s\n' 'Secret scan passed.'
