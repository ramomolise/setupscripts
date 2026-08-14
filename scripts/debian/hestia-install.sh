#!/usr/bin/env bash
set -Eeuo pipefail

hostname_value=''
email=''
port='8083'
admin_user='admin'
generated_password=false
force_install=false
assume_yes=false

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/debian/hestia-install.sh [options]

Options:
  --hostname HOST        Fully qualified server hostname
  --email ADDRESS        Administrator email address
  --port PORT            Hestia panel port (default: 8083)
  --username USER        Hestia administrator (default: admin)
  --generate-password    Generate a password and save it in /root
  --force                Allow a non-fresh host and pass --force upstream
  --yes                  Skip the final confirmation
  -h, --help             Show this help

Passwords are never accepted as command-line arguments, where shell history and
process listings could expose them.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

prompt_value() {
    local label=$1
    local default_value=${2:-}
    local value=''

    if [[ -n "$default_value" ]]; then
        read -r -p "$label [$default_value]: " value
        printf '%s' "${value:-$default_value}"
    else
        read -r -p "$label: " value
        printf '%s' "$value"
    fi
}

while (($#)); do
    case "$1" in
        --hostname) [[ $# -ge 2 ]] || die '--hostname needs a value.'; hostname_value=$2; shift ;;
        --email) [[ $# -ge 2 ]] || die '--email needs a value.'; email=$2; shift ;;
        --port) [[ $# -ge 2 ]] || die '--port needs a value.'; port=$2; shift ;;
        --username) [[ $# -ge 2 ]] || die '--username needs a value.'; admin_user=$2; shift ;;
        --generate-password) generated_password=true ;;
        --force) force_install=true ;;
        --yes) assume_yes=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID == 0)) || die 'Run this installer as root.'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'

# shellcheck source=/etc/os-release
source /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
    debian:11|debian:12|debian:13|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
    *) die "Unsupported operating system: ${PRETTY_NAME:-unknown}" ;;
esac

case "$(uname -m)" in
    x86_64|aarch64|arm64) ;;
    *) die 'HestiaCP requires a supported 64-bit AMD64 or ARM64 system.' ;;
esac

if [[ -z "$hostname_value" ]]; then
    [[ -t 0 ]] || die 'Use --hostname in non-interactive mode.'
    hostname_value=$(prompt_value 'Server hostname, for example host.example.com')
fi
if [[ -z "$email" ]]; then
    [[ -t 0 ]] || die 'Use --email in non-interactive mode.'
    email=$(prompt_value 'Administrator email')
fi

hostname_regex='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
email_regex='^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
[[ "$hostname_value" =~ $hostname_regex ]] || die 'Hostname must be a fully qualified domain name.'
[[ "$email" =~ $email_regex ]] || die 'Email address format is invalid.'
[[ "$port" =~ ^[0-9]+$ ]] || die 'Port must be a number.'
((port >= 1 && port <= 65535)) || die 'Port must be between 1 and 65535.'
[[ "$admin_user" =~ ^[a-z][a-z0-9_-]{0,30}$ ]] || die 'Administrator username is invalid.'

conflicting_packages=()
for package_name in apache2 nginx mariadb-server mysql-server exim4; do
    if dpkg-query -W -f='${db:Status-Status}\n' "$package_name" 2>/dev/null | grep -q '^installed$'; then
        conflicting_packages+=("$package_name")
    fi
done

if ((${#conflicting_packages[@]})) && ! $force_install; then
    printf '%s\n' 'HestiaCP should be installed on a fresh operating system.' >&2
    printf '%s\n' 'Existing server packages were detected:' >&2
    printf '  %s\n' "${conflicting_packages[@]}" >&2
    die 'Use a fresh host, or review the risk and rerun with --force.'
fi

if $generated_password; then
    command -v openssl >/dev/null 2>&1 || die 'openssl is required to generate a password.'
    password=$(openssl rand -base64 30 | tr -d '\n')
else
    [[ -t 0 ]] || die 'Use --generate-password in non-interactive mode.'
    while :; do
        read -r -s -p 'Administrator password: ' password
        printf '\n'
        read -r -s -p 'Confirm password: ' password_confirmation
        printf '\n'
        [[ "$password" == "$password_confirmation" ]] || {
            printf '%s\n' 'Passwords do not match. Try again.' >&2
            continue
        }
        ((${#password} >= 12)) || {
            printf '%s\n' 'Use at least 12 characters.' >&2
            continue
        }
        break
    done
fi

printf '%s\n' '' 'HestiaCP installation summary'
printf '  Operating system: %s\n' "${PRETTY_NAME:-unknown}"
printf '  Hostname:         %s\n' "$hostname_value"
printf '  Panel URL:        https://%s:%s\n' "$hostname_value" "$port"
printf '  Email:            %s\n' "$email"
printf '  Administrator:    %s\n' "$admin_user"
printf '  Password:         %s\n' 'hidden'
printf '  Force install:    %s\n' "$force_install"

if ! $assume_yes; then
    read -r -p 'Type INSTALL to continue: ' confirmation
    [[ "$confirmation" == 'INSTALL' ]] || die 'Installation cancelled.'
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl

tmp_dir=$(mktemp -d /tmp/hestia-install.XXXXXX)
cleanup() {
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

installer="$tmp_dir/hst-install.sh"
curl --fail --show-error --silent --location \
    https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh \
    --output "$installer"

installer_args=(
    --port "$port"
    --interactive no
    --email "$email"
    --password "$password"
    --hostname "$hostname_value"
    --username "$admin_user"
)
$force_install && installer_args+=(--force)

if $generated_password; then
    credentials_file="/root/hestia-initial-credentials-$(date +%Y%m%d-%H%M%S).txt"
    umask 077
    {
        printf 'Panel: https://%s:%s\n' "$hostname_value" "$port"
        printf 'Username: %s\n' "$admin_user"
        printf 'Password: %s\n' "$password"
    } >"$credentials_file"
    chmod 0600 "$credentials_file"
    printf 'Generated credentials saved to %s (root only).\n' "$credentials_file"
fi

bash "$installer" "${installer_args[@]}"
unset password

printf '%s\n' 'HestiaCP installer completed.'
printf 'Open: https://%s:%s\n' "$hostname_value" "$port"
