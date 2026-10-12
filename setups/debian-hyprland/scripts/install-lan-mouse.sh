#!/usr/bin/env bash
set -Eeuo pipefail

version=v0.11.0
expected_sha256=c43d211ec1af3eaea0cd585ac5c415776000355c3fcb9742fa2513f32dab55ba
url="https://github.com/feschber/lan-mouse/releases/download/$version/lan-mouse-linux-x86_64"

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

((EUID != 0)) || die 'Run this installer as your normal desktop user.'
[[ $(uname -m) == x86_64 ]] || die 'This pinned binary installer currently supports x86_64 only.'
for command_name in curl sha256sum sudo install; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_root=$(cd -- "$script_dir/../config" && pwd)
download=$(mktemp)
trap 'rm -f "$download"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 --output "$download" "$url"
printf '%s  %s\n' "$expected_sha256" "$download" | sha256sum --check --status || die 'Lan Mouse checksum verification failed.'
sudo install -o root -g root -m 0755 "$download" /usr/local/bin/lan-mouse

install -d "$HOME/.config/systemd/user" "$HOME/.config/lan-mouse"
install -m 0644 "$config_root/systemd/user/lan-mouse.service" "$HOME/.config/systemd/user/lan-mouse.service"
if [[ ! -e $HOME/.config/lan-mouse/config.toml && ! -e $HOME/.config/lan-mouse/config.toml.example ]]; then
    install -m 0600 "$config_root/lan-mouse/config.toml.example" "$HOME/.config/lan-mouse/config.toml.example"
fi
systemctl --user daemon-reload
systemctl --user enable lan-mouse.service

printf '%s\n' \
    "Lan Mouse $version installed and checksum verified." \
    'Edit ~/.config/lan-mouse/config.toml.example, save it as config.toml, then run:' \
    '  systemctl --user restart lan-mouse.service' \
    'Authorize this Debian machine fingerprint on the laptop and allow UDP 4242 on the LAN only.'
