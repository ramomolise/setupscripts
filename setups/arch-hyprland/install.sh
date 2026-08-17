#!/usr/bin/env bash
set -Eeuo pipefail

install_packages=true

usage() {
    cat <<'EOF'
Usage: ./setups/arch-hyprland/install.sh [--no-packages]

  --no-packages   Only deploy configuration files and the wallpaper
  -h, --help      Show this help
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --no-packages) install_packages=false ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID != 0)) || die 'Run this installer as your normal user, not root.'
[[ -r /etc/arch-release ]] || die 'This setup supports native Arch Linux.'
command -v sudo >/dev/null 2>&1 || die 'sudo is required.'
command -v pacman >/dev/null 2>&1 || die 'pacman is required.'

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
packages_file="$script_dir/packages.txt"
config_root="$script_dir/config"

mapfile -t packages < <(awk 'NF && $1 !~ /^#/' "$packages_file")
((${#packages[@]})) || die 'No packages were found.'

if $install_packages; then
    printf 'Installing %d official Arch packages...\n' "${#packages[@]}"
    sudo pacman -Syu --needed --noconfirm "${packages[@]}"
    sudo systemctl enable --now NetworkManager.service
    sudo systemctl enable --now bluetooth.service
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_root="$HOME/.local/state/ramo-setups/backups/$timestamp/arch-hyprland"
install -d -m 0700 "$backup_root"

for config_name in hypr waybar wofi; do
    destination="$HOME/.config/$config_name"
    if [[ -e "$destination" ]]; then
        cp -a -- "$destination" "$backup_root/$config_name"
    fi
    install -d "$destination"
    cp -a -- "$config_root/$config_name/." "$destination/"
done

wallpaper_dir="$HOME/.local/share/backgrounds"
wallpaper="$wallpaper_dir/rm-architect.png"
install -d "$wallpaper_dir" "$HOME/Pictures/Screenshots"
command -v rsvg-convert >/dev/null 2>&1 || die 'rsvg-convert is required. Install the librsvg package.'
rsvg-convert --width 3840 --height 2160 \
    "$repo_root/assets/rm-architect.svg" >"$wallpaper"

sed "s|@WALLPAPER@|$wallpaper|g" \
    "$config_root/hypr/hyprpaper.conf.in" >"$HOME/.config/hypr/hyprpaper.conf"
rm -f -- "$HOME/.config/hypr/hyprpaper.conf.in"

if systemctl --user list-unit-files hyprpolkitagent.service >/dev/null 2>&1; then
    systemctl --user enable hyprpolkitagent.service || true
fi

printf '%s\n' '' 'Arch Hyprland setup installed.'
printf 'Backup directory: %s\n' "$backup_root"
printf '%s\n' 'Log out, start Hyprland, then adjust monitor lines if needed.'
