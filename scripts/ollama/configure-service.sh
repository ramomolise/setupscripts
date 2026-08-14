#!/usr/bin/env bash
set -Eeuo pipefail

bind_address='127.0.0.1:11434'
context_length='65536'
parallel='2'
max_queue='64'
keep_alive='24h'
allow_all_interfaces=false
assume_yes=false

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/ollama/configure-service.sh [options]

Options:
  --host ADDRESS        Ollama bind address (default: 127.0.0.1:11434)
  --context NUMBER      Context length (default: 65536)
  --parallel NUMBER     Parallel requests (default: 2)
  --max-queue NUMBER    Maximum queued requests (default: 64)
  --keep-alive VALUE    Model keep-alive time (default: 24h)
  --allow-all-interfaces
                        Required if --host uses 0.0.0.0 or [::]
  --yes                 Skip confirmation

This configures Ollama only. It does not open a firewall port or configure a
reverse proxy. Prefer loopback, a private LAN address, or a private overlay
network instead of exposing port 11434 publicly.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --host) [[ $# -ge 2 ]] || die '--host needs a value.'; bind_address=$2; shift ;;
        --context) [[ $# -ge 2 ]] || die '--context needs a value.'; context_length=$2; shift ;;
        --parallel) [[ $# -ge 2 ]] || die '--parallel needs a value.'; parallel=$2; shift ;;
        --max-queue) [[ $# -ge 2 ]] || die '--max-queue needs a value.'; max_queue=$2; shift ;;
        --keep-alive) [[ $# -ge 2 ]] || die '--keep-alive needs a value.'; keep_alive=$2; shift ;;
        --allow-all-interfaces) allow_all_interfaces=true ;;
        --yes) assume_yes=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID == 0)) || die 'Run this script as root.'
command -v systemctl >/dev/null 2>&1 || die 'systemctl is required.'
systemctl cat ollama.service >/dev/null 2>&1 || die 'ollama.service is not installed.'

host_regex='^([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):([0-9]{1,5})$'
[[ "$bind_address" =~ $host_regex ]] || die 'Host must look like 127.0.0.1:11434.'
bind_port=${BASH_REMATCH[2]}
((bind_port >= 1 && bind_port <= 65535)) || die 'Host port must be between 1 and 65535.'
for numeric_value in "$context_length" "$parallel" "$max_queue"; do
    [[ "$numeric_value" =~ ^[1-9][0-9]*$ ]] || die "Invalid positive number: $numeric_value"
done
[[ "$keep_alive" =~ ^(-1|[0-9]+(ms|s|m|h))$ ]] || die 'Keep-alive must be a duration such as 24h, or -1.'

case "$bind_address" in
    0.0.0.0:*|'[::]':*)
        $allow_all_interfaces || die 'Binding every interface requires --allow-all-interfaces.'
        ;;
esac

printf '%s\n' 'Ollama service configuration'
printf '  Bind address:  %s\n' "$bind_address"
printf '  Context:       %s\n' "$context_length"
printf '  Parallel:      %s\n' "$parallel"
printf '  Max queue:     %s\n' "$max_queue"
printf '  Keep alive:    %s\n' "$keep_alive"

if ! $assume_yes; then
    read -r -p 'Type CONFIGURE to continue: ' confirmation
    [[ "$confirmation" == 'CONFIGURE' ]] || die 'Configuration cancelled.'
fi

dropin_dir='/etc/systemd/system/ollama.service.d'
dropin_file="$dropin_dir/override.conf"
install -d -m 0755 "$dropin_dir"
if [[ -f "$dropin_file" ]]; then
    backup_file="$dropin_file.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a -- "$dropin_file" "$backup_file"
    printf 'Existing override backed up to %s\n' "$backup_file"
fi

{
    printf '%s\n' '[Service]'
    printf 'Environment="OLLAMA_HOST=%s"\n' "$bind_address"
    printf 'Environment="OLLAMA_CONTEXT_LENGTH=%s"\n' "$context_length"
    printf 'Environment="OLLAMA_NUM_PARALLEL=%s"\n' "$parallel"
    printf 'Environment="OLLAMA_MAX_QUEUE=%s"\n' "$max_queue"
    printf 'Environment="OLLAMA_KEEP_ALIVE=%s"\n' "$keep_alive"
} >"$dropin_file"

systemctl daemon-reload
systemd-analyze verify ollama.service >/dev/null
systemctl restart ollama.service
systemctl --no-pager --full status ollama.service | sed -n '1,12p'

printf '%s\n' 'Ollama service configured. Review firewall and access controls separately.'
