# Ramo's Setup Scripts

Reproducible Linux workstation, server, AI-runtime, and diagnostic tooling built
from systems I actually use. The main targets are Debian 13, Proxmox VE, Qtile,
Arch Linux, Hyprland, HestiaCP, Ollama, and Hermes.

The repository favours readable scripts, backups, explicit confirmation, and
read-only diagnosis before mutation. It intentionally contains no Docker
installer: Docker's official documentation is the better maintained source for
that job.

## Setups

| Setup | Target | Purpose |
|---|---|---|
| [RM Architect Qtile](setups/debian-qtile/README.md) | Debian 13 / Proxmox desktop | Qtile, Picom, Dunst, Rofi, Firefox styling, branded wallpaper, and 60% keyboard-friendly shortcuts |
| [Arch Hyprland](setups/arch-hyprland/README.md) | Native Arch Linux | Current Hyprland desktop using official repository packages and hardware-neutral defaults |
| [Forge runtime](setups/forge-runtime/README.md) | Debian/Linux | Isolated Hermes/Ollama runtime, health checks, and optional public-profile hardening |

## Administration scripts

| Script | What it does |
|---|---|
| [`scripts/proxmox/reclaim-local-lvm.sh`](scripts/proxmox/reclaim-local-lvm.sh) | On a new Proxmox installation, removes an empty `local-lvm` thin pool and gives the free space to the root filesystem |
| [`scripts/debian/hestia-install.sh`](scripts/debian/hestia-install.sh) | Interactive, validated HestiaCP installer that does not echo the admin password |
| [`scripts/debian/hestia-roundcube-repair.sh`](scripts/debian/hestia-roundcube-repair.sh) | Backs up and repairs the narrow Roundcube permission case seen on HestiaCP |
| [`scripts/ollama/configure-service.sh`](scripts/ollama/configure-service.sh) | Creates a backed-up systemd override for Ollama tuning and controlled network binding |
| [`scripts/ollama/health-check.sh`](scripts/ollama/health-check.sh) | Checks native and OpenAI-compatible Ollama endpoints without exposing prompts or credentials |
| [`scripts/general/custom-resolution.sh`](scripts/general/custom-resolution.sh) | Creates and applies a parameterised X11 display mode |

## Read-only diagnostics

- [`system-report.sh`](scripts/diagnostics/system-report.sh) — OS, CPU, memory, storage, services, and virtualization overview.
- [`audio-report.sh`](scripts/diagnostics/audio-report.sh) — ALSA and PipeWire/PulseAudio cards, sinks, ports, and defaults.
- [`gpu-passthrough-report.sh`](scripts/diagnostics/gpu-passthrough-report.sh) — IOMMU, PCI GPU, VFIO, kernel, and Proxmox checks.

Reports avoid network addresses and credentials by default. Review output before
sharing it publicly.

## Safety levels

- **Read-only:** diagnostic and health-check tools.
- **User configuration:** desktop installers; existing files are backed up.
- **System configuration:** Hestia and Ollama tools; require root or `sudo`.
- **Destructive:** Proxmox storage reclaim; refuses to run when it detects guest
  volumes and requires a typed confirmation.

Run scripts from a cloned copy so relative assets are available:

```bash
git clone https://github.com/ramomolise/setupscripts.git
cd setupscripts
```

Each setup has its own README and usage command. Never pipe a script from the
internet directly into a privileged shell.

## Validate a contribution

```bash
make check
```

The check runs Bash syntax validation, a tracked-file secret scan, Python
configuration compilation, `git diff --check`, and ShellCheck when installed.

## Documentation and recovery checklists

- [Hestia/OCI recovery](docs/hestia-oci-recovery.md)
- [Private Ollama access](docs/ollama-private-access.md)
- [GPU passthrough workflow](docs/gpu-passthrough-workflow.md)

## Licence

[MIT](LICENSE.md)
