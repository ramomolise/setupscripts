# Arch Hyprland setup

A clean Hyprland desktop for a native Arch Linux installation. It uses only
official repository packages: there is no AUR helper bootstrap and no cloned
dotfiles repository left behind in your home directory.

The configuration uses automatic monitor detection, PipeWire, NetworkManager,
Bluetooth, Waybar, Wofi, Kitty, Thunar, Hyprpaper, Hyprlock, Hypridle, and the
Hyprland PolicyKit agent.

## Install

Run as your normal user with working `sudo` access:

```bash
./setups/arch-hyprland/install.sh
```

Use `--no-packages` to redeploy only the configuration and wallpaper.

Existing `hypr`, `waybar`, and `wofi` configuration directories are copied to:

```text
~/.local/state/ramo-setups/backups/<timestamp>/
```

After installation, log out and start `Hyprland` from your display manager or
TTY. The installer does not change bootloader, display-manager, GPU-driver, or
kernel settings.

## Main shortcuts

| Shortcut | Action |
|---|---|
| `Super + Return` | Terminal |
| `Super + Space` | Application launcher |
| `Super + E` | File manager |
| `Super + B` | Firefox |
| `Super + Q` | Close window |
| `Super + F` | Fullscreen |
| `Super + V` | Toggle floating |
| `Super + L` | Lock |
| `Print` | Select an area and save a screenshot |
| `Super + 1…9` | Switch workspace |

Monitor-specific changes belong at the top of
`~/.config/hypr/hyprland.conf`.
