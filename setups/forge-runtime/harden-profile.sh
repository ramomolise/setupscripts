#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -ge 1 ]] || {
    printf '%s\n' 'Usage: harden-profile.sh PROFILE [--apply] [--restart]' >&2
    exit 2
}

profile=$1
shift
apply=false
restart=false

while (($#)); do
    case "$1" in
        --apply) apply=true ;;
        --restart) restart=true ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

[[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf '%s\n' 'Profile name contains unsupported characters.' >&2
    exit 2
}
command -v hermes >/dev/null 2>&1 || {
    printf '%s\n' 'hermes is not installed.' >&2
    exit 1
}

printf 'Profile: %s\n' "$profile"
printf '%s\n' 'Planned controls:'
printf '%s\n' '  - disable memory'
printf '%s\n' '  - disable user profile'
printf '%s\n' '  - add memory to disabled toolsets'
printf '%s\n' '  - disable the memory tool'
$restart && printf '%s\n' '  - restart and check the profile gateway'

if ! $apply; then
    printf '%s\n' '' 'Dry run only. Add --apply after reviewing the plan.'
    exit 0
fi

hermes_home=${HERMES_HOME:-$HOME/.hermes}
soul_file="$hermes_home/profiles/$profile/SOUL.md"
if [[ -f "$soul_file" ]]; then
    soul_backup="$soul_file.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$soul_file" "$soul_backup"
    printf 'SOUL backup: %s\n' "$soul_backup"
fi

hermes -p "$profile" config set memory.memory_enabled false
hermes -p "$profile" config set memory.user_profile_enabled false
hermes -p "$profile" config set agent.disabled_toolsets '["memory"]'
hermes -p "$profile" tools disable memory

if $restart; then
    hermes -p "$profile" gateway restart
    hermes -p "$profile" gateway status
fi

printf '%s\n' 'Profile hardening applied. Test it with synthetic prompts before production use.'
