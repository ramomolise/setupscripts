#!/usr/bin/env bash
set -Eeuo pipefail

install_packages=true
style_firefox=true
force_os=false

usage() {
    cat <<'EOF'
Usage: ./setups/debian-qtile/install.sh [options]

Options:
  --no-packages     Only deploy configuration files
  --skip-firefox    Do not modify Firefox profiles
  --force-os        Allow a Debian release other than 13
  -h, --help        Show this help
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --no-packages) install_packages=false ;;
        --skip-firefox) style_firefox=false ;;
        --force-os) force_os=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

((EUID != 0)) || die 'Run this installer as your normal desktop user.'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'

# shellcheck source=/etc/os-release
source /etc/os-release
if [[ ${ID:-} != 'debian' || ${VERSION_ID:-} != '13' ]]; then
    $force_os || die "Expected Debian 13; found ${PRETTY_NAME:-unknown}. Use --force-os to override."
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
config_root="$script_dir/config"
packages_file="$script_dir/packages.txt"

if $install_packages; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required to install packages.'
    mapfile -t packages < <(awk 'NF && $1 !~ /^#/' "$packages_file")
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_root="$HOME/.local/state/rm-architect/backups/$timestamp"
install -d -m 0700 "$backup_root"

for config_name in qtile picom dunst rofi; do
    destination="$HOME/.config/$config_name"
    if [[ -e "$destination" ]]; then
        cp -a -- "$destination" "$backup_root/$config_name"
    fi
    install -d "$destination"
    cp -a -- "$config_root/$config_name/." "$destination/"
done
chmod 0755 "$HOME/.config/qtile/autostart.sh"

wallpaper_dir="$HOME/.local/share/backgrounds"
wallpaper="$wallpaper_dir/rm-architect.png"
install -d "$wallpaper_dir" "$HOME/Pictures/Screenshots"
command -v rsvg-convert >/dev/null 2>&1 || die 'rsvg-convert is required. Install librsvg2-bin.'
rsvg-convert --width 3840 --height 2160 \
    "$repo_root/assets/rm-architect.svg" >"$wallpaper"

if $style_firefox; then
    firefox_root="$HOME/.mozilla/firefox"
    profiles_found=0
    if [[ -d "$firefox_root" ]]; then
        while IFS= read -r -d '' profile; do
            profiles_found=$((profiles_found + 1))
            profile_name=$(basename "$profile")
            if [[ -e "$profile/chrome" ]]; then
                install -d "$backup_root/firefox/$profile_name"
                cp -a -- "$profile/chrome" "$backup_root/firefox/$profile_name/chrome"
            fi
            [[ -e "$profile/user.js" ]] && {
                install -d "$backup_root/firefox/$profile_name"
                cp -a -- "$profile/user.js" "$backup_root/firefox/$profile_name/user.js"
            }

            install -d "$profile/chrome"
            cp -a -- "$config_root/firefox/chrome/." "$profile/chrome/"

            user_js="$profile/user.js"
            if grep -q '^user_pref("toolkit.legacyUserProfileCustomizations.stylesheets"' "$user_js" 2>/dev/null; then
                sed -i 's/^user_pref("toolkit\.legacyUserProfileCustomizations\.stylesheets".*/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);/' "$user_js"
            else
                printf '%s\n' 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >>"$user_js"
            fi
        done < <(find "$firefox_root" -mindepth 1 -maxdepth 1 -type d -name '*.default*' -print0)
    fi
    if ((profiles_found == 0)); then
        printf '%s\n' 'Firefox profile not found; launch Firefox once and rerun with --no-packages.'
    fi
fi

printf '%s\n' '' 'RM Architect Qtile setup installed.'
printf 'Backup directory: %s\n' "$backup_root"
printf '%s\n' 'Log out and select Qtile from your session menu.'
