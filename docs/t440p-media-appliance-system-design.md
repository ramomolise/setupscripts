# T440p media appliance system design

Status: **design specification, not an installer**

Target: bare Lenovo ThinkPad T440p motherboard used as an always-on media/server appliance.

This document is normative guidance for future implementation. Codex or another maintainer should be able to scan this repository, read this file, and understand the intended architecture, dependencies, service boundaries, key bindings, recovery model, and acceptance criteria without reverse-engineering decisions from chat history.

Do **not** turn this document into a one-shot install script unless a later task explicitly asks for one. Prefer small, reviewable configuration files, helper programs, service units, and diagnostics that match the conventions already used in this repository.

---

## 1. Physical platform and assumptions

The machine is **not a normal laptop anymore**. Treat it as a bare motherboard appliance.

Retained hardware:

- Lenovo ThinkPad T440p motherboard
- CPU
- RAM
- internal Wi-Fi card
- Wi-Fi antennas
- boot/storage device as required by the final deployment

Removed / unavailable hardware:

- laptop chassis/covers
- internal LCD panel
- internal keyboard
- TrackPoint
- touchpad
- battery-dependent laptop workflow
- normal lid-switch semantics

External I/O:

- display: mini DisplayPort -> HDMI -> TV/monitor
- input: wired USB keyboard with integrated touchpad/mouse surface
- network: internal Wi-Fi
- optional Bluetooth: headphones, speakers, game controllers, other accessories

Design consequence: this should behave like a **small headless server that happens to expose a browser UI over HDMI**.

The external USB keyboard is the only guaranteed local control path. Bluetooth must never be required to recover the machine.

---

## 2. Design goals

Priority order:

1. reliable media appliance behaviour
2. low idle RAM and minimal graphical overhead
3. standard Debian/systemd administration
4. Docker-host reliability independent of the graphical session
5. simple non-technical media usage
6. easy local admin mode when required
7. SSH recovery if the graphical stack fails
8. avoid unnecessary desktop daemons and background services

Explicit non-goals:

- no GNOME/KDE/XFCE desktop environment
- no always-running panel, dock, launcher, notification centre, wallpaper service, desktop indexer, or file indexer
- no custom window manager implementation
- no browser `--kiosk` mode that removes normal tabs/address-bar behaviour
- no dependence on Bluetooth for basic control
- no Docker installer maintained by this repository
- no hard-coded storage device names such as `/dev/sda`
- no hard-coded UID such as `1000`
- no passwords, tokens, Wi-Fi credentials, VPN credentials, API keys, or other secrets committed to Git

---

## 3. High-level architecture

```text
Bare T440p motherboard
|
+-- Debian 13 / Trixie
|   |
|   +-- systemd
|   |   +-- NetworkManager
|   |   +-- sshd
|   |   +-- nftables
|   |   +-- bluetooth.service / BlueZ
|   |   +-- smartd
|   |   +-- avahi-daemon (recommended)
|   |   +-- docker.service
|   |   +-- containerd.service
|   |   +-- greetd.service
|   |   +-- triggerhappy.service
|   |
|   +-- user audio session
|   |   +-- PipeWire
|   |   +-- pipewire-pulse
|   |   +-- WirePlumber
|   |
|   +-- graphical session selection
|       |
|       +-- INITIAL SESSION: Media mode
|       |   +-- Cage
|       |       +-- t440p-media-controller
|       |           +-- Firefox ESR
|       |           +-- temporary foot utility windows
|       |
|       +-- DEFAULT LOGIN: tuigreet
|           +-- Qtile Admin session (X11)
|           +-- Media session (manual return)
|
+-- Docker media stack
    +-- Jellyfin
    +-- Jellyseerr
    +-- Sonarr
    +-- Radarr
    +-- Prowlarr
    +-- qBittorrent
```

The **Docker stack must not depend on Cage, Firefox, Qtile, greetd, or a logged-in graphical user**. If the entire local UI crashes, media automation and server services continue running.

---

## 4. Session model

### 4.1 Normal boot

Normal power-on behaviour:

```text
firmware
  -> Debian
  -> systemd services
  -> Docker containers
  -> greetd initial_session
  -> Cage
  -> Firefox ESR
  -> Netflix homepage
```

No login screen should be shown during a normal boot.

Use greetd's `initial_session` mechanism for the automatic media login. Important: greetd initial sessions are intended to run **once after boot**. When the session later exits, greetd should fall back to its normal greeter rather than immediately auto-logging in again.

That behaviour is desirable here.

### 4.2 Leaving media mode

`Super + Q` in media mode means **Exit Media Mode**, not close the current browser tab.

Expected flow:

```text
Cage / Firefox
  -> t440p-media-controller receives exit request
  -> controller performs clean child shutdown
  -> Cage exits
  -> greetd detects no active session
  -> tuigreet appears
```

### 4.3 Admin mode

From tuigreet, authenticate normally and select **Qtile Admin**.

Qtile Admin is a conventional maintenance desktop for:

- Firefox/documentation
- terminal work
- copy/paste between browser and terminal
- Docker administration
- logs and diagnostics
- `pavucontrol`
- Bluetooth administration
- file management if required
- repository work
- system configuration

Reuse the existing `setups/debian-qtile` design where practical instead of duplicating the entire Qtile configuration.

### 4.4 Returning to media mode

Logging out of Qtile returns to tuigreet. The user can select the Media session and authenticate, or reboot to get the normal automatic media boot path.

Do not implement insecure password bypasses merely to make the manual return path one click shorter.

---

## 5. Display manager / greeter

Use:

- `greetd`
- `tuigreet`

Do not use SDDM, GDM, or LightDM unless a later requirement makes greetd unsuitable.

Rationale:

- minimal footprint
- systemd-friendly
- supports a one-time initial auto-login session
- can return to a normal login after media logout
- tuigreet can discover both Wayland and X11 sessions

The final configuration should expose at least two session entries:

- `T440p Media`
- `Qtile Admin`

For X11 sessions, tuigreet/startx handling must be verified instead of assuming that invoking `qtile` directly on a bare VT starts Xorg. Tuigreet supports an X-session wrapper and normally uses `startx /usr/bin/env` for X11 desktop entries. Preserve this behaviour or provide an explicit tested wrapper.

---

## 6. Media compositor

Use **Cage**.

Debian 13/Trixie ships Cage 0.2.x. Cage is deliberately narrow: one maximized visible application at a time. This is desirable for the media session.

Launch Cage with VT switching enabled:

```text
cage -s -- <media-controller>
```

`-s` must remain enabled so VT switching remains available as an emergency local recovery path.

Do not use Sway for the normal media session unless future requirements need true multi-window tiling in media mode. Qtile already exists for admin work.

---

## 7. Why a media controller is required

Do not make system-wide Triggerhappy handlers launch Wayland applications directly.

A system daemon does not naturally own the Cage session's `WAYLAND_DISPLAY`, D-Bus session, PipeWire user environment, or user runtime directory. Direct GUI launches from Triggerhappy would therefore be fragile.

Instead, Cage should launch a small user-space controller as its child:

```text
Cage
  -> t440p-media-controller
       -> Firefox
       -> control socket
       -> temporary utilities on request
```

Recommended implementation language: Python 3 standard library unless a shell implementation remains clearly simpler and equally robust.

No third-party Python packages should be necessary.

### 7.1 Controller responsibilities

The controller must:

- run as the normal interactive user, never root
- inherit Cage's valid Wayland environment
- create a private Unix socket under `$XDG_RUNTIME_DIR`
- set socket permissions to user-only (`0600` semantics)
- start Firefox ESR
- supervise Firefox
- restart Firefox after unexpected termination with bounded/backoff behaviour
- distinguish intentional Media Mode exit from Firefox crash
- spawn temporary Wayland utilities such as `foot`
- accept only an allow-listed command set
- reject arbitrary command execution
- clean up its socket on exit

Recommended socket path:

```text
$XDG_RUNTIME_DIR/t440p-media/control.sock
```

Do not hard-code `/run/user/1000`.

### 7.2 Control protocol

A tiny newline-delimited protocol is sufficient. The controller should accept only explicit actions such as:

```text
volume-up
volume-down
mute
play-pause
next
previous
open-audio
open-bluetooth
browser-home
exit-media
status
```

No command may carry a shell fragment.

### 7.3 Client

Provide a small `t440p-media-ctl` client that:

- locates the expected socket
- sends one allow-listed action
- returns a useful exit status
- fails quietly for media-only hotkeys when media mode is not running
- supports a `status` action suitable for diagnostics/tests

---

## 8. Firefox design

Use Debian's Firefox ESR unless a later requirement explicitly chooses another channel.

Firefox should be a **normal browser occupying a maximized Cage surface**, not Firefox kiosk mode.

Required behaviour:

- normal tab bar
- normal address bar
- normal browser shortcuts
- Netflix homepage
- YouTube accessible normally
- Jellyfin bookmark
- Jellyseerr bookmark
- uBlock Origin managed or pre-provisioned
- DRM playback enabled for Netflix
- Wayland-native mode preferred

Recommended environment:

```text
MOZ_ENABLE_WAYLAND=1
```

Do not disable normal browser controls.

### 8.1 Browser policies

A future implementation may use Firefox enterprise policies for reproducible defaults.

Desired policy outcomes:

- homepage: Netflix
- uBlock Origin installed/managed
- avoid telemetry/promo clutter where supported without breaking media sites
- do not disable DRM
- do not disable password/profile features unless explicitly required
- do not store secrets in repository policy files

Do not manually ship Widevine binaries. Firefox should obtain supported DRM components through its normal mechanism.

### 8.2 Browser key bindings

Leave Firefox's own standard bindings intact:

| Keys | Action |
|---|---|
| `Ctrl + T` | new tab |
| `Ctrl + W` | close tab |
| `Ctrl + L` | focus address bar |
| `Ctrl + Tab` | next tab |
| `Ctrl + Shift + Tab` | previous tab |
| `Ctrl + R` | reload |
| `Ctrl + F` | find |
| `Alt + Left` | back |
| `Alt + Right` | forward |
| `F11` | optional Firefox chrome fullscreen |

The normal appliance state should not require `F11`; Cage already gives Firefox the full display surface.

---

## 9. Hotkey architecture

Use **Triggerhappy** as the low-level input event listener.

Reason:

- system-wide
- independent of X11/Wayland
- works well for appliance/hardware controls
- supports key combinations
- handles hot-plugged input devices

The daemon must **not grab the keyboard exclusively**. Qtile and Firefox still need normal key events.

All Triggerhappy actions should call one narrow dispatcher, for example:

```text
/usr/local/bin/t440p-hotkey <action>
```

The dispatcher must not accept arbitrary commands.

### 9.1 Session-aware dispatch

The dispatcher should check for the media controller socket.

If media mode is active:

- send the action to `t440p-media-ctl`

If media mode is not active:

- media-only actions should exit successfully without doing anything
- allow Qtile to receive and handle the same keyboard event normally

This is important because the existing Qtile configuration already uses some overlapping shortcuts.

Example:

- `Super + B` in Media Mode -> Bluetooth manager
- `Super + B` in Qtile -> existing Qtile Firefox shortcut

Triggerhappy sees both, but outside Media Mode the dispatcher deliberately no-ops, so Qtile remains authoritative.

### 9.2 Verify real keycodes

Do not assume every USB keyboard emits exactly the expected Linux input symbols.

Before finalizing Triggerhappy config, use its event dump/list tooling against the actual USB keyboard and record the emitted events for:

- volume up
- volume down
- mute
- play/pause
- next
- previous
- left/right Super/Meta

Bind both left and right Meta variants if the keyboard can emit either.

---

## 10. Required media-mode key bindings

These bindings are the target UX.

### Hardware media keys

| Input | Media Mode action |
|---|---|
| `Volume Up` | default sink +5%, repeat supported, cap at sane maximum |
| `Volume Down` | default sink -5%, repeat supported |
| `Mute` | toggle default sink mute |
| `Play/Pause` | control active Firefox media via MPRIS/playerctl |
| `Next` | next item where the active site/player exposes it |
| `Previous` | previous item where the active site/player exposes it |

Recommended volume cap: do not exceed 150% without an explicit later decision.

### Appliance shortcuts

| Shortcut | Media Mode action | Qtile behaviour |
|---|---|---|
| `Super + B` | open Bluetooth manager | preserve existing Firefox shortcut |
| `Super + A` | open audio output selector | free for Qtile unless later assigned |
| `Super + H` | browser home / Netflix | Qtile may retain its own layout meaning; Triggerhappy no-ops outside Media Mode |
| `Super + Q` | exit Media Mode to greetd | existing Qtile close-window action remains authoritative in Qtile |

Do not bind `Super + Enter` in Media Mode by default. Terminal work belongs in Qtile Admin. This keeps the appliance surface simple.

Optional future binding:

- `Super + J` -> open Jellyfin
- `Super + Y` -> open YouTube

Only add those if direct site launch is actually useful; normal browser tabs/bookmarks may be enough.

---

## 11. Audio stack

Use:

- `pipewire`
- `pipewire-pulse`
- `wireplumber`
- `libspa-0.2-bluetooth`
- `pavucontrol` for Qtile Admin only

Primary CLI control:

- `wpctl`

Expected operations:

```text
wpctl set-volume ...
wpctl set-mute ...
wpctl set-default ...
```

WirePlumber should remain the policy/session manager.

### 11.1 Media-mode audio selector

`Super + A` should ask the controller to launch a temporary `foot` utility window.

Desired UX:

```text
Audio output

> HDMI / TV
  Bluetooth headphones
  USB audio device
```

Selecting an item makes it the default PipeWire sink and closes the utility. Firefox becomes visible again automatically.

Implementation preference:

- lightweight terminal UI
- no layer-shell dependency
- no always-running tray applet
- avoid parsing unstable/localized output where a machine-readable PipeWire/WirePlumber interface is available
- if CLI parsing is unavoidable, force `LC_ALL=C` and cover parsing with tests

### 11.2 Audio fallback

Preferred policy:

1. keep the currently remembered usable default
2. if a newly connected Bluetooth audio device is explicitly selected/connected by the user, make it default
3. otherwise prefer active HDMI when present
4. fall back to another valid local sink

Do not steal audio automatically merely because an unrelated Bluetooth device appears.

---

## 12. Bluetooth design

Use BlueZ:

- `bluez`
- `bluetooth.service`
- `bluetoothctl`

Bluetooth is optional convenience, not critical control infrastructure.

### 12.1 Media-mode Bluetooth manager

`Super + B` should request a temporary `foot` utility through the media controller.

Base implementation must work with Debian-native tooling.

Minimum supported actions:

- adapter power on/off
- scan
- list discovered devices
- list paired devices
- pair
- trust
- connect
- disconnect
- remove/forget
- show connection state

A small repository-owned helper/TUI may wrap `bluetoothctl` to make these common actions obvious.

Do not make `bluetuith` a hard dependency of the base design because it is not a normal Debian 13 package and is currently an external project. It may be supported later as an optional enhanced UI.

Pairing flows that require a PIN, confirmation, or passkey must remain visible and interactive in the terminal utility.

### 12.2 Bluetooth audio

After the user connects a Bluetooth audio device, the helper may offer to make the corresponding PipeWire sink the default.

Never assume every Bluetooth device is an audio sink.

---

## 13. Qtile Admin mode

Qtile Admin should reuse the repository's existing Debian Qtile configuration as the baseline.

Existing expected admin bindings include:

| Shortcut | Action |
|---|---|
| `Super + Return` | terminal |
| `Super + Space` | launcher |
| `Super + E` | file manager |
| `Super + B` | Firefox |
| `Super + H/J/K/L` | focus navigation |
| `Super + Shift + H/J/K/L` | move windows |
| `Super + Ctrl + H/L` | resize |
| `Super + F` | fullscreen |
| `Super + V` | floating toggle |
| `Super + Q` | close window |
| `Super + 1..9` | switch workspace |
| `Super + Shift + 1..9` | send window to workspace |
| `Print` | screenshot |
| `Super + Ctrl + R` | reload Qtile |

Qtile's current audio bindings should remain valid. Ensure the system Triggerhappy dispatcher no-ops when the media controller socket is absent so volume changes are not doubled.

For this appliance, remove or disable irrelevant desktop-specific features only if doing so does not break the reusable Qtile setup elsewhere in the repository. Prefer a T440p-specific overlay/config instead of degrading the generic `debian-qtile` setup.

---

## 14. Terminal choice

Preferred lightweight Wayland terminal for temporary Cage utilities:

- `foot`

Admin Qtile may continue using the terminal already defined by the existing Qtile setup unless a later refactor standardizes on one terminal.

Cage utility windows should be short-lived. Closing the utility should reveal Firefox again.

---

## 15. Core Debian dependencies

The implementation should document and verify these package groups rather than blindly installing large metapackages.

### Base / administration

- `systemd` / standard Debian base
- `sudo`
- `openssh-server`
- `network-manager`
- `nftables`
- `dbus-user-session`
- `ca-certificates`
- `curl` only where genuinely required
- `git` for admin/repo work

### Graphics / sessions

- `greetd`
- `tuigreet`
- `cage`
- `firefox-esr`
- `foot`
- `qtile`
- Xorg packages required for Qtile X11
- `xinit` / `startx` path required by tuigreet X-session wrapping
- Mesa/Intel graphics userspace appropriate for Haswell Intel graphics

### Audio / media control

- `pipewire`
- `pipewire-pulse`
- `wireplumber`
- `libspa-0.2-bluetooth`
- `pavucontrol`
- `playerctl`

### Bluetooth / input

- `bluez`
- `triggerhappy`

### Health / appliance support

- `smartmontools`
- `lm-sensors`
- `unattended-upgrades`
- `avahi-daemon` (recommended)

### Optional helper dependencies

Only add if the implementation actually uses them:

- `jq`
- `fzf`
- `dialog`

Avoid installing packages merely because a full desktop normally includes them.

---

## 16. Docker runtime expectations

This repository should **not** become a Docker Engine installer. Follow Docker's maintained Debian installation guidance outside this design.

Expected runtime components if using Docker's official packages:

- Docker Engine
- Docker CLI
- containerd
- Compose plugin
- Buildx plugin if needed

Docker starts through systemd before any graphical login.

Container restart policy should normally be:

```yaml
restart: unless-stopped
```

Do not make Docker service success depend on Wi-Fi reaching the internet; local containers should still come up and recover when networking returns.

---

## 17. Media container stack

Target stack:

- Jellyfin
- Jellyseerr
- Sonarr
- Radarr
- Prowlarr
- qBittorrent

### Responsibilities

**Jellyfin**

- media library and playback UI
- local browser target
- should have read-only access to completed media wherever possible

**Jellyseerr**

- simple request interface for non-technical household users
- preferred request UX instead of exposing Sonarr/Radarr directly

**Sonarr**

- TV-series automation

**Radarr**

- movie automation

**Prowlarr**

- indexer management shared by Sonarr/Radarr

**qBittorrent**

- download client
- WebUI restricted to LAN/admin use

### 17.1 Storage layout recommendation

Prefer one consistent data tree so Sonarr/Radarr/qBittorrent see matching paths and hardlinks/atomic moves remain possible when storage permits.

Recommended logical host layout:

```text
/srv/data/
├── downloads/
│   ├── incomplete/
│   └── complete/
└── media/
    ├── movies/
    └── tv/

/srv/appdata/
├── jellyfin/
├── jellyseerr/
├── sonarr/
├── radarr/
├── prowlarr/
└── qbittorrent/
```

Recommended container convention:

- qBittorrent, Sonarr, and Radarr mount `/srv/data` consistently as `/data`
- Sonarr TV root: `/data/media/tv`
- Radarr movie root: `/data/media/movies`
- qBittorrent downloads: `/data/downloads/...`
- Jellyfin mounts `/srv/data/media` read-only where practical

Avoid separate, inconsistent `/downloads`, `/movies`, `/tv` host mappings that force remote-path translation and prevent hardlink-friendly moves.

Physical disks must be mounted by UUID or similarly stable identifiers. Never encode `/dev/sdX` names as durable configuration.

---

## 18. Docker network exposure

Baseline LAN services commonly include:

- SSH: 22/tcp
- Jellyfin: 8096/tcp unless changed
- Jellyseerr: 5055/tcp unless changed
- Sonarr: 8989/tcp unless changed
- Radarr: 7878/tcp unless changed
- Prowlarr: 9696/tcp unless changed
- qBittorrent WebUI: deployment-defined, commonly 8080/tcp

These are design defaults, not an instruction to open all ports globally.

Firewall policy:

- allow required services from trusted LAN only
- do not expose Sonarr/Radarr/Prowlarr/qBittorrent directly to the public internet
- do not punch WAN holes automatically
- if remote access is later required, use a deliberately designed VPN/reverse-proxy/authentication solution
- account for Docker's own packet-filter rules; do not assume a simple host firewall rule automatically constrains every published Docker port

---

## 19. Optional torrent/VPN isolation

If torrent traffic later needs to traverse a VPN, isolate qBittorrent's network path rather than tunnelling the whole appliance by default.

Desired properties:

- qBittorrent loses external connectivity if the tunnel fails
- Sonarr/Radarr/Prowlarr can still reach qBittorrent over the intended internal path
- Jellyfin local playback does not depend on the VPN
- SSH/admin access does not accidentally disappear into the tunnel
- DNS-leak and kill-switch behaviour is testable

This is optional and outside the first implementation milestone.

---

## 20. Networking

Use NetworkManager for Wi-Fi.

Recommendations:

- stable hostname, e.g. `media` or `t440p-media`
- DHCP reservation in the router instead of hard-coding a static IP inside Debian where possible
- `avahi-daemon` for convenient `.local` discovery

Example convenience names:

```text
http://t440p-media.local:8096  Jellyfin
http://t440p-media.local:5055  Jellyseerr
http://t440p-media.local:8989  Sonarr
http://t440p-media.local:7878  Radarr
http://t440p-media.local:9696  Prowlarr
```

Do not commit Wi-Fi SSIDs or passphrases.

---

## 21. SSH and recovery

OpenSSH is **mandatory** for this hardware configuration.

Rationale: there is no built-in LCD/keyboard/touchpad fallback. If HDMI, Cage, greetd, or the USB keyboard fails, SSH is the practical recovery path.

Recommended end state:

- key-based SSH authentication
- disable SSH password login after keys are confirmed working
- no direct root SSH login
- LAN firewall restriction

Useful recovery commands should remain conventional Debian/systemd commands:

```text
systemctl status greetd
journalctl -b
journalctl -u greetd
systemctl status docker
docker ps
systemctl status bluetooth
loginctl session-status
```

Keep VT switching enabled in Cage as a second local fallback.

---

## 22. Power management

Treat the board as an always-on appliance, not a portable laptop.

Desired behaviour:

- no automatic suspend
- no hibernate
- no hybrid sleep
- ignore lid-related actions
- short physical power-button press performs an orderly shutdown
- no random desktop power manager

Do not blindly mask targets until the effect has been tested against clean shutdown/reboot and system maintenance workflows. Implement the smallest explicit logind/systemd policy necessary.

Firmware recommendation: if the T440p firmware exposes a reliable "power on after AC restore / power on with AC attach" option, consider enabling it for appliance recovery after an outage.

---

## 23. Health monitoring

Install and use:

- `smartmontools`
- `lm-sensors`

### Storage

`smartd` should monitor supported disks used for OS/media/download storage.

Alerting can be added later; the first requirement is that failure indicators are visible in logs and diagnostics.

### Thermals

Because the motherboard operates outside its original chassis, validate temperatures under real workloads:

- browser video playback
- Jellyfin direct play
- Jellyfin transcoding
- sustained qBittorrent traffic
- unpack/move activity
- simultaneous Docker workload

Do not install custom fan control initially. Prefer the ThinkPad firmware/EC behaviour unless testing proves it inadequate.

---

## 24. Updates

Use `unattended-upgrades` for security updates.

Do not configure automatic reboot while media may be in use.

A later maintenance policy may add a controlled reboot window, but first implementation should leave reboot decisions explicit.

Docker image updates should not be blindly automated with an uncontrolled updater. Prefer reviewed/intentional image updates until rollback and health checks are defined.

---

## 25. Services intentionally omitted by default

Do not install/enable unless a concrete need appears:

- CUPS
- ModemManager
- geoclue
- GNOME services
- KDE services
- desktop search/indexing
- PackageKit
- full desktop Bluetooth applets
- full desktop network applets
- desktop power managers
- wallpaper daemons
- panels/docks
- notification daemons for Media Mode
- TLP by default
- custom fan daemons by default
- `udisks2` unless interactive removable-drive workflows require it

Qtile Admin may use selected desktop utilities where useful, but they should not become persistent Media Mode dependencies.

---

## 26. Proposed repository implementation layout

A future implementation should remain modular and reviewable. Suggested structure:

```text
setups/t440p-media-appliance/
├── README.md
├── config/
│   ├── greetd/
│   │   └── config.toml
│   ├── tuigreet/
│   │   └── config.toml
│   ├── triggerhappy/
│   │   └── t440p-media.conf
│   ├── firefox/
│   │   └── policies.json
│   └── sessions/
│       ├── t440p-media.desktop
│       └── qtile-admin.desktop
├── bin/
│   ├── t440p-media-controller
│   ├── t440p-media-ctl
│   ├── t440p-hotkey
│   ├── t440p-audio-menu
│   └── t440p-bluetooth-menu
├── systemd/
│   └── optional narrowly-scoped units only
├── tests/
│   ├── test_media_controller.py
│   ├── test_hotkey_dispatch.py
│   └── fixtures/
└── docs/
    └── recovery.md
```

This layout is descriptive, not mandatory. Follow existing repository conventions if a cleaner structure is already established.

No `install.sh` is required by this design.

---

## 27. Configuration ownership and privilege boundaries

Principles:

- Cage/Firefox/controller run as the normal user
- no graphical application runs as root
- root-owned Triggerhappy config can invoke only the narrow dispatcher
- the dispatcher exposes a fixed allow-list
- media control socket is user-private
- Docker administration should acknowledge that membership in the `docker` group is effectively root-equivalent
- prefer `sudo docker ...` if the convenience/security trade-off has not been consciously accepted
- no world-writable control sockets
- no shell interpolation of data received over the control socket

---

## 28. Failure behaviour

### Firefox crashes

Expected:

```text
Firefox exits unexpectedly
  -> controller waits briefly
  -> Firefox restarts
  -> repeated rapid failure triggers backoff
```

Avoid a hot restart loop consuming CPU.

### Cage crashes

The greetd-managed Media session ends. The greeter should become available rather than leaving the machine unusable.

A future systemd/session wrapper may add controlled retry, but never create an infinite rapid respawn loop that prevents admin login.

### Docker container crashes

Docker restart policy recovers the individual container.

### Wi-Fi drops

Local graphical session remains usable. Docker services remain running. NetworkManager reconnects when possible.

### Bluetooth fails

USB keyboard/touchpad and HDMI still provide local control. Bluetooth failure must never lock the user out.

### HDMI/display fails

SSH remains the primary recovery path.

### USB keyboard fails

SSH remains the primary recovery path.

---

## 29. Logging and diagnostics

Use journald rather than inventing a parallel log stack.

Controller/helper programs should log concise messages to stderr so the session/service supervisor captures them.

Never log:

- browser cookies
- passwords
- Wi-Fi credentials
- API keys
- torrent tracker credentials
- full private URLs containing tokens

Recommended future diagnostic command/report should include:

- current session type
- Cage/controller process state
- controller socket state
- Firefox process state
- PipeWire/WirePlumber state
- default sink
- Bluetooth adapter/device summary
- greetd state
- Docker container state
- disk SMART summary
- temperatures
- storage mounts

Prefer extending the repository's read-only diagnostic philosophy instead of making "repair" commands mutate the system automatically.

---

## 30. Security model

This is a household appliance, not a hardened multi-user server, but basic boundaries still matter.

Required:

- normal user session, not root
- `sudo` password for privileged admin work
- SSH keys before disabling password SSH
- LAN-only management interfaces by default
- no public exposure of Arr/qBittorrent interfaces
- no secrets in Git
- firewall rules documented and testable
- browser kept updated through Debian security updates
- Docker images updated intentionally

Autologin into Media Mode is acceptable because it only grants the expected living-room browser surface. It must not silently grant a privileged shell.

---

## 31. Current Debian 13 assumptions

Verified design assumptions for Debian 13/Trixie at the time this document was written:

- Cage is available in Debian stable and supports `-s` for VT switching.
- greetd supports a one-time `initial_session` followed by the default greeter after logout.
- tuigreet is available in Debian stable and supports Wayland/X11 session discovery; X11 sessions can be wrapped through `startx`.
- Qtile is available in Debian stable as an X11 window manager.
- foot is available as a lightweight native Wayland terminal.
- Triggerhappy is available and supports system-wide hotkeys, key combinations, hotplugging, and command dispatch.
- BlueZ is available as the standard Bluetooth stack.
- PipeWire/WirePlumber are available and are the intended audio stack.
- playerctl is available for MPRIS media control.

Do not pin exact package versions in implementation unless there is a demonstrated compatibility reason. Debian security/stable updates should remain installable.

---

## 32. Implementation order for Codex

When explicitly asked to implement this design, use small reviewable steps in this order:

1. inspect current repository state and existing Debian/Qtile helpers
2. add T440p appliance documentation/readme skeleton
3. add session wrappers and desktop entries
4. add greetd/tuigreet configuration templates
5. implement media controller and control client with tests
6. implement hotkey dispatcher with tests
7. add Triggerhappy config
8. implement audio menu
9. implement Bluetooth menu
10. add Firefox policy/config templates
11. integrate/reuse Qtile Admin session without duplicating generic Qtile setup
12. add read-only diagnostics
13. document Docker/storage layout without writing a Docker installer
14. add validation checklist
15. only then consider optional conveniences

Do not combine all steps into an opaque monolithic script.

---

## 33. Acceptance criteria

The design is successfully implemented only when all of the following are true.

### Boot and sessions

- cold boot reaches Firefox/Netflix without interactive login
- no full desktop environment is running in Media Mode
- `Super + Q` exits Media Mode and exposes tuigreet
- Qtile Admin can be selected and authenticated normally
- logging out of Qtile returns to tuigreet
- Media session can be selected manually from the greeter

### Browser

- Firefox has normal tabs/address bar
- Netflix loads
- YouTube loads
- Jellyfin is reachable
- Jellyseerr is reachable
- uBlock Origin is present as designed
- DRM playback is functional

### Input

- USB keyboard/touchpad works from booted Media Mode
- hardware volume up/down/mute work
- play/pause works when Firefox exposes controllable media
- `Super + B` opens Bluetooth utility in Media Mode
- `Super + A` opens audio selection utility in Media Mode
- these Media Mode actions do not break the existing Qtile bindings

### Audio

- HDMI audio can be selected
- Bluetooth audio can be selected after pairing/connection
- default output changes persist appropriately
- pavucontrol works in Qtile Admin

### Bluetooth

- scan works
- pair works
- trust works
- connect/disconnect works
- remove works
- a Bluetooth failure does not affect wired USB control

### Server side

- Docker starts without graphical login
- required containers survive Media Mode logout
- container restart policy recovers a crashed service
- storage paths are consistent between qBittorrent/Sonarr/Radarr
- Jellyfin can read completed media

### Recovery

- SSH works while Cage is broken/stopped
- VT switching works from Cage
- greetd state is diagnosable through journald
- a Firefox crash does not permanently strand the display
- a failed utility window can be closed to return to Firefox

### Resource discipline

- no GNOME/KDE/XFCE session is required
- no panel/dock/tray is required in Media Mode
- no graphical Bluetooth/audio applet runs persistently
- no unnecessary indexing/search daemon is enabled

---

## 34. Final design principle

The machine should be thought of as:

> **server first, browser appliance second, desktop only when deliberately requested**

The normal household experience is Firefox on HDMI with working media keys and lightweight Bluetooth/audio controls.

The administration experience is a conventional Qtile workstation reached intentionally through greetd.

The server experience is standard Debian + systemd + Docker, independent of both graphical modes.
