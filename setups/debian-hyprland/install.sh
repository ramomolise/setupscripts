#!/usr/bin/env bash
set -Eeuo pipefail

install_packages=true
enable_backports=true
configure_igpu=true
force_os=false
igpu_pci=''
shell_mode=auto

usage() {
    cat <<'EOF'
Usage: ./setups/debian-hyprland/install.sh [options]

Options:
  --no-packages          Only deploy configuration files
  --no-enable-backports  Require trixie-backports to be configured already
  --no-igpu-rule         Do not install the stable /dev/dri/amd-igpu udev link
  --igpu-pci ADDRESS     AMD iGPU PCI address (otherwise auto-detect exactly one)
  --shell MODE           auto, quickshell, or waybar (default: auto)
  --force-os             Allow a Debian release other than 13
  -h, --help             Show this help

The installer keeps Qtile installed and does not change the default session.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

normalise_pci() {
    local address=$1
    [[ $address == 0000:* ]] || address="0000:$address"
    printf '%s\n' "${address,,}"
}

while (($#)); do
    case "$1" in
        --no-packages) install_packages=false ;;
        --no-enable-backports) enable_backports=false ;;
        --no-igpu-rule) configure_igpu=false ;;
        --igpu-pci)
            [[ $# -ge 2 ]] || die '--igpu-pci requires a value.'
            igpu_pci=$(normalise_pci "$2")
            shift
            ;;
        --shell)
            [[ $# -ge 2 ]] || die '--shell requires a value.'
            shell_mode=$2
            shift
            ;;
        --force-os) force_os=true ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
done

case "$shell_mode" in
    auto|quickshell|waybar) ;;
    *) die '--shell must be auto, quickshell, or waybar.' ;;
esac

((EUID != 0)) || die 'Run this installer as your normal desktop user.'
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'

# shellcheck source=/etc/os-release
source /etc/os-release
if [[ ${ID:-} != debian || ${VERSION_ID:-} != 13 ]]; then
    $force_os || die "Expected Debian 13; found ${PRETTY_NAME:-unknown}. Use --force-os to override."
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
config_root="$script_dir/config"

if $install_packages; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required to install packages.'

    if $enable_backports && ! grep -Rqs '^[^#].*trixie-backports' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        backports_tmp=$(mktemp)
        trap 'rm -f "${backports_tmp:-}"' EXIT
        cat >"$backports_tmp" <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
        sudo install -o root -g root -m 0644 "$backports_tmp" /etc/apt/sources.list.d/trixie-backports.sources
    fi

    mapfile -t stable_packages < <(awk 'NF && $1 !~ /^#/' "$script_dir/packages.txt")
    mapfile -t backports_packages < <(awk 'NF && $1 !~ /^#/' "$script_dir/backports-packages.txt")
    sudo apt-get update
    sudo apt-get install -y "${stable_packages[@]}"
    sudo apt-get install -y -t trixie-backports "${backports_packages[@]}"

fi

if [[ $shell_mode != waybar ]] && ! command -v qs >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
    warn 'Quickshell is not installed; the staged configuration will use Waybar until it is available.'
fi

command -v rsvg-convert >/dev/null 2>&1 || die 'rsvg-convert is required. Install librsvg2-bin.'
[[ -r $repo_root/assets/rm-architect.svg ]] || die 'The RM Architect wallpaper asset is missing.'

if $configure_igpu; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required to install the iGPU udev rule.'
    if [[ -z $igpu_pci ]]; then
        mapfile -t amd_displays < <(
            for device in /sys/bus/pci/devices/*; do
                [[ -r $device/vendor && -r $device/class ]] || continue
                [[ $(<"$device/vendor") == 0x1002 && $(<"$device/class") == 0x03* ]] || continue
                basename "$device"
            done
        )
        ((${#amd_displays[@]} == 1)) || die 'Expected exactly one AMD display controller; pass --igpu-pci ADDRESS.'
        igpu_pci=${amd_displays[0]}
    fi

    [[ $igpu_pci =~ ^0000:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[0-7]$ ]] || die 'Invalid --igpu-pci address.'
    [[ -d /sys/bus/pci/devices/$igpu_pci ]] || die "PCI device is not present: $igpu_pci"
    [[ $(<"/sys/bus/pci/devices/$igpu_pci/vendor") == 0x1002 ]] || die "$igpu_pci is not an AMD device."
    [[ $(<"/sys/bus/pci/devices/$igpu_pci/class") == 0x03* ]] || die "$igpu_pci is not a display controller."

    rule_tmp=$(mktemp)
    trap 'rm -f "${backports_tmp:-}" "${rule_tmp:-}"' EXIT
    printf '%s\n' \
        "KERNEL==\"card*\", KERNELS==\"$igpu_pci\", SUBSYSTEM==\"drm\", SUBSYSTEMS==\"pci\", SYMLINK+=\"dri/amd-igpu\"" \
        >"$rule_tmp"
    sudo install -o root -g root -m 0644 "$rule_tmp" /etc/udev/rules.d/80-rm-amd-igpu.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=drm
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_root="$HOME/.local/state/rm-architect/backups/$timestamp/debian-hyprland"
install -d -m 0700 "$backup_root"

for config_name in hypr quickshell waybar; do
    destination="$HOME/.config/$config_name"
    if [[ -e $destination ]]; then
        mv -- "$destination" "$backup_root/$config_name"
    fi
    install -d "$destination"
    cp -a -- "$config_root/$config_name/." "$destination/"
done

install -d "$HOME/.config/rm-architect" "$HOME/.local/bin" "$HOME/Pictures/Screenshots"
printf '%s\n' "$shell_mode" >"$HOME/.config/rm-architect/shell-mode"
install -m 0755 "$script_dir/scripts/rm-shell-start" "$HOME/.local/bin/rm-shell-start"
install -m 0755 "$script_dir/scripts/rm-keybinds" "$HOME/.local/bin/rm-keybinds"
install -m 0755 "$script_dir/scripts/rm-hypr-input-capture" "$HOME/.local/bin/rm-hypr-input-capture"

wallpaper_dir="$HOME/.local/share/backgrounds"
wallpaper="$wallpaper_dir/rm-architect.png"
install -d "$wallpaper_dir"
rsvg-convert --width 3840 --height 2160 "$repo_root/assets/rm-architect.svg" >"$wallpaper"
sed "s|@WALLPAPER@|$wallpaper|g" "$config_root/hypr/hyprpaper.conf.in" >"$HOME/.config/hypr/hyprpaper.conf"

printf '\n%s\n' 'Debian Hyprland prototype installed.'
printf 'Backup directory: %s\n' "$backup_root"
printf 'AMD compositor device: %s\n' "${igpu_pci:-not configured by this run}"
printf '%s\n' \
    'Qtile remains installed. Log out and select Hyprland from the session menu.' \
    'Install Lan Mouse separately with: setups/debian-hyprland/scripts/install-lan-mouse.sh'
