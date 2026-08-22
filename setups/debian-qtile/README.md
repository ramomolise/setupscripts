# RM Architect Qtile setup

The reproducible version of Ramo's Debian 13 / Proxmox desktop: Qtile on X11,
Picom GLX composition, Dunst notifications, Rofi, UKUI PolicyKit, a restrained
black/graphite/silver/deep-purple palette, Firefox ESR styling, and a full
Ramo Molise wordmark wallpaper without the old circular emblem.

The shortcuts avoid relying on dedicated function keys, which makes the setup
comfortable on a Redragon FIZZ and other 60% keyboards.

## Install

Run this from the cloned repository as your normal desktop user:

```bash
./setups/debian-qtile/install.sh
```

Options:

```text
--no-packages      Only deploy configuration files
--skip-firefox     Do not change Firefox profiles
--force-os         Allow a Debian release other than 13
```

Existing configuration and Firefox chrome directories are backed up under:

```text
~/.local/state/rm-architect/backups/<timestamp>/
```

The desktop installer does not modify Proxmox networking, storage, repositories,
bootloader, kernel parameters, or GPU passthrough configuration.

After installation, log out and select **Qtile** from the display-manager
session menu. If Firefox has never been opened, launch it once and rerun with
`--no-packages` so its profile can be styled.

## Optional RTX 3090 / Windows VM toggle

`Super + Shift + G` calls a separately installed, guarded Proxmox GPU switch.
It is inert until the system component is explicitly installed with a real VM
ID. Read the complete prerequisites and failure boundaries first:

- [Live GPU passthrough switch](../../docs/gpu-passthrough-workflow.md)

The switch restarts the X11 login session in both directions. This is required
so Xorg can discover or release the hot-rebound NVIDIA GPU without rebooting the
entire host. Save open work before confirming the Rofi prompt.

`Super + G` launches Steam with NVIDIA PRIME render-offload variables. Keep the
monitor on the Ryzen iGPU output for the reliable no-HDMI-swap layout.

## Main shortcuts

| Shortcut | Action |
|---|---|
| `Super + Return` | Alacritty terminal |
| `Super + Space` | Rofi launcher |
| `Super + E` | Thunar file manager |
| `Super + B` | Firefox ESR |
| `Super + G` | Steam using NVIDIA PRIME |
| `Super + Shift + G` | Confirm GPU/VM mode toggle |
| `Super + H/J/K/L` | Move focus |
| `Super + Shift + H/J/K/L` | Move window |
| `Super + Ctrl + H/L` | Resize layout |
| `Super + F` | Fullscreen |
| `Super + V` | Toggle floating |
| `Super + Q` | Close window |
| `Super + 1…9` | Switch workspace |
| `Super + Shift + 1…9` | Send window to workspace |
| `Print` | Save a screenshot |
| `Super + Ctrl + R` | Reload Qtile |

The `Fn` key on a 60% keyboard is handled by the keyboard firmware, so Qtile
cannot bind it directly. Standard volume and brightness media events are still
supported when the keyboard emits them.
