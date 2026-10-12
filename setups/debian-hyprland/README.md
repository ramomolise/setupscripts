# Debian Hyprland prototype

A reversible Debian 13 / Proxmox desktop profile: Hyprland 0.55+ Lua
configuration, Dusky-inspired keybindings and modularity, an experimental
Quickshell bar, a Waybar fallback, Lan Mouse, and the existing guarded RTX 3090
passthrough switch.

This is deliberately not a Dusky clone. Dusky's structure and keyboard flow are
the inspiration; Debian packaging, the AMD-iGPU-only compositor boundary, and
Quickshell are specific to this machine and future distro prototype.

## Safety model

Hyprland receives `AQ_DRM_DEVICES=/dev/dri/amd-igpu`. The installer creates that
stable link only after validating an AMD display-class PCI device. Hyprland must
never open the detachable RTX, so `Super + Shift + G` can continue to hand it
between the Debian host and Windows VM through the guarded switch.

Qtile is not removed, the default display-manager session is not changed, and
existing Hyprland/Quickshell/Waybar configuration is backed up below
`~/.local/state/rm-architect/backups/`.

## Install

From this repository, as the normal desktop user:

```bash
./setups/debian-hyprland/install.sh
```

The installer enables official `trixie-backports` when needed. Use
`--no-enable-backports` to manage APT sources yourself. If more than one AMD
display controller exists, select the Ryzen iGPU explicitly:

```bash
./setups/debian-hyprland/install.sh --igpu-pci 0000:0a:00.0
```

Shell choices are `--shell auto`, `--shell quickshell`, and `--shell waybar`.
`auto` prefers Quickshell when its executable is available, otherwise Waybar.
The Quickshell configuration is installed now, but the profile does not mix
Debian testing into stable to obtain the executable. Until Quickshell is
available from a repository you trust, the same session starts Waybar.

After installation, log out and select **Hyprland**. Keep Qtile until the GPU
toggle, suspend/resume, screen lock, portal sharing, and Lan Mouse have passed
the checklist below.

## GPU switch

Install the system switch separately if it is not already present:

```bash
sudo ./scripts/proxmox/install-gpu-passthrough-switch.sh --vmid 999
```

- `Super + Shift + G`: confirm and toggle RTX ownership.
- `Super + G`: launch Steam with NVIDIA render offload.

The display manager restarts during ownership changes, so save work first.
The Hyprland session and its `graphical-session.target` services will be stopped
as part of that restart. See the full [GPU workflow](../../docs/gpu-passthrough-workflow.md).

## Lan Mouse: Debian host controls laptop

Install the pinned v0.11.0 x86_64 binary and user service:

```bash
./setups/debian-hyprland/scripts/install-lan-mouse.sh
```

Then copy `~/.config/lan-mouse/config.toml.example` to `config.toml`, enter the
laptop hostname/IP, and restart `lan-mouse.service`. To see the Debian host's
certificate fingerprint, temporarily stop the user service and launch the GTK
frontend with `lan-mouse`; authorize that fingerprint on the laptop, close the
frontend, then restart the service. Open UDP 4242 only on the trusted LAN.

Keep this topology one-way initially: define the laptop as a client only on the
Debian host, and do not define the Debian host as a client on the laptop. Both
machines should use the same Lan Mouse release.

## Prototype limitations

- Quickshell is still pre-1.0 and is not in Debian 13 backports. Its config is
  ready, but Waybar is the supported fallback while packaging is evaluated.
- Lan Mouse v0.11.0 has an open Hyprland 0.56 reconnect/crash report
  ([issue 478](https://github.com/feschber/lan-mouse/issues/478)); the proposed
  fix is tracked in [PR 491](https://github.com/feschber/lan-mouse/pull/491).
  The one-way topology reduces connection churn but does not replace testing.
- The initial session should be tested locally before relying on Lan Mouse as
  the only input path.

## Acceptance checklist

1. `readlink -f /dev/dri/amd-igpu` resolves to the AMD DRM card.
2. `hyprctl systeminfo` and `ls -l /dev/dri/by-path/` show Hyprland on AMD.
3. The RTX can switch VM -> host -> VM with no game, CUDA, or Ollama clients.
4. Suspend/resume and a full reboot preserve the intended VM ownership state.
5. Quickshell starts, or Waybar takes over without delaying the session.
6. Lan Mouse crosses the selected screen edge and releases with A+S+D+F.
7. Qtile can still be selected from the display manager as the rollback path.

## Main shortcuts

| Shortcut | Action |
|---|---|
| `Super + Q/W/E` | Terminal / browser / files |
| `Alt + Space` | Rofi application launcher |
| `Ctrl + Shift + Space` | Shortcut reference |
| `Super + C` | Close window |
| `Super + A/D` | Toggle fullscreen / floating |
| `Alt + Tab` | Cycle windows |
| `Super + Tab` | Return to previous workspace |
| `Super + Arrow keys` | Move focus |
| `Super + Shift + Arrow keys` | Move window |
| `Super + 1…9/0` | Switch to workspace 1–10 |
| `Super + Shift + 1…9/0` | Send window to workspace 1–10 |
| `Super + mouse-left/right` | Move / resize floating window |
| `Super + G` | Steam using NVIDIA PRIME |
| `Super + Shift + G` | Guarded RTX/VM toggle |
| `Print` | Region screenshot |
