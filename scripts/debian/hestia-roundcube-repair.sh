#!/usr/bin/env bash
set -Eeuo pipefail

apply=false
[[ ${1:-} == '--apply' ]] && apply=true
[[ $# -le 1 ]] || {
    printf '%s\n' 'Usage: sudo hestia-roundcube-repair.sh [--apply]' >&2
    exit 2
}

((EUID == 0)) || {
    printf '%s\n' 'Run this script as root.' >&2
    exit 1
}

roundcube_dir='/etc/roundcube'
[[ -d "$roundcube_dir" ]] || {
    printf 'Roundcube directory not found: %s\n' "$roundcube_dir" >&2
    exit 1
}
getent passwd hestiamail >/dev/null || {
    printf '%s\n' 'The hestiamail user does not exist.' >&2
    exit 1
}
getent group hestiamail >/dev/null || {
    printf '%s\n' 'The hestiamail group does not exist.' >&2
    exit 1
}

printf '%s\n' 'Planned repair:'
printf '  Back up %s\n' "$roundcube_dir"
printf '%s\n' '  Set owner to hestiamail:hestiamail'
printf '%s\n' '  Set PHP configuration files to mode 0640'

if ! $apply; then
    printf '%s\n' '' 'Dry run only. Rerun with --apply after reviewing the plan.'
    exit 0
fi

backup_file="/root/roundcube-etc-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -C /etc -czf "$backup_file" roundcube
chown -R hestiamail:hestiamail "$roundcube_dir"
find "$roundcube_dir" -type f -name '*.php' -exec chmod 0640 {} +

printf 'Repair complete. Backup: %s\n' "$backup_file"
