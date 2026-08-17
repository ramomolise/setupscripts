#!/usr/bin/env bash
set -Eeuo pipefail

readonly vg_name='pve'
readonly data_lv="/dev/${vg_name}/data"
readonly root_lv="/dev/${vg_name}/root"
assume_yes=false

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/proxmox/reclaim-local-lvm.sh [--yes]

For a new Proxmox VE installation only. The script removes an EMPTY local-lvm
thin pool and extends the root filesystem into the released space.

It refuses to continue if it detects logical volumes stored in the data pool.
This is not a VM migration or backup tool.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (($#)); do
    case "$1" in
        --yes) assume_yes=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID == 0)) || die 'Run this script as root.'

for command_name in pveversion pvesm lvs vgs findmnt lvremove lvextend; do
    require_command "$command_name"
done

[[ -d /etc/pve ]] || die 'This does not look like a Proxmox VE host.'
[[ -e "$data_lv" ]] || die "$data_lv does not exist or was already removed."
[[ -e "$root_lv" ]] || die "$root_lv does not exist."

root_source=$(readlink -f "$(findmnt -n -o SOURCE /)")
expected_root=$(readlink -f "$root_lv")
[[ "$root_source" == "$expected_root" ]] || {
    die "The mounted root filesystem is $root_source, not $root_lv."
}

root_fstype=$(findmnt -n -o FSTYPE /)
case "$root_fstype" in
    ext2|ext3|ext4|xfs) ;;
    *) die "Unsupported root filesystem for automatic growth: $root_fstype" ;;
esac

mapfile -t guest_lvs < <(
    lvs --noheadings --separator '|' -o lv_name,pool_lv "$vg_name" |
        awk -F'|' '
            {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            }
            $2 == "data" && $1 != "data" { print $1 }
        '
)

if ((${#guest_lvs[@]})); then
    printf '%s\n' 'Refusing to remove local-lvm. These volumes use the data pool:' >&2
    printf '  %s\n' "${guest_lvs[@]}" >&2
    exit 1
fi

printf '%s\n' 'Preflight passed.'
printf '  Proxmox: %s\n' "$(pveversion | head -n1)"
printf '  Thin pool to remove: %s\n' "$data_lv"
printf '  Root LV to extend:   %s\n' "$root_lv"
printf '  Root filesystem:     %s\n' "$root_fstype"
printf '%s\n' ''
lvs "$vg_name"

if ! $assume_yes; then
    printf '%s\n' ''
    printf '%s\n' 'This permanently removes the pve/data thin pool.'
    read -r -p 'Type RECLAIM to continue: ' confirmation
    [[ "$confirmation" == 'RECLAIM' ]] || die 'Confirmation not received.'
fi

backup_dir="/root/proxmox-storage-backups/$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$backup_dir"
cp --archive /etc/pve/storage.cfg "$backup_dir/storage.cfg"

if pvesm status 2>/dev/null | awk '$1 == "local-lvm" { found=1 } END { exit !found }'; then
    printf '%s\n' 'Removing the local-lvm entry from Proxmox storage configuration...'
    pvesm remove local-lvm
fi

printf '%s\n' "Removing empty thin pool $data_lv..."
lvremove --yes "$data_lv"

printf '%s\n' "Extending $root_lv and growing $root_fstype..."
lvextend --resizefs -l +100%FREE "$root_lv"

printf '%s\n' ''
printf '%s\n' 'Storage reclaim completed.'
printf '  Configuration backup: %s\n' "$backup_dir/storage.cfg"
df -hT /
lvs "$vg_name"
