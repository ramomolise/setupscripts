# Live GPU passthrough switch

This workflow is for the `axiom` layout: Proxmox VE on the bare-metal Debian 13
host, Qtile on X11 using the Ryzen 7 5700G iGPU, and an RTX 3090 that normally
belongs to an autostarting Windows 11 VM running Ollama.

It adds a guarded `Super + Shift + G` toggle. It does not force-stop Windows and
does not change the VM, IOMMU, bootloader, initramfs, or NVIDIA driver setup.

## What the toggle does

### Passthrough to Linux host

1. Requests a graceful Windows shutdown through `qm shutdown`.
2. Waits until Proxmox reports the VM as stopped.
3. Restarts the X11 login session so it can discover the newly available GPU.
4. Rebinds the RTX display function to `nvidia` and its audio function to
   `snd_hda_intel`.
5. Starts the display manager again and returns to the login screen.

Log in, then press `Super + G` to launch Steam with NVIDIA PRIME render-offload
variables.

### Linux host to passthrough

1. Refuses to continue while a game, CUDA task, Ollama, or another non-X11 GPU
   client is detected.
2. Restarts the login session to release X11's NVIDIA handles.
3. Unloads the NVIDIA modules and binds both PCI functions to `vfio-pci`.
4. Starts the Windows VM and restores the login screen on the iGPU.

No forced guest stop is used. If Windows does not shut down within the configured
timeout, the switch fails and leaves the guest alone.

## Display cable reality

The dependable no-cable-swap layout is to keep the monitor connected to the
motherboard/iGPU. Qtile is always displayed by AMDGPU; only selected Linux apps
render on the RTX through PRIME. NVIDIA documents this as one GPU rendering an
application while another GPU presents the result.

A cable connected only to the RTX cannot simultaneously provide a stable host
display while that GPU is owned by the VM. Reverse PRIME can expose NVIDIA
outputs after an X11 restart, but monitor input switching and hot-added output
behaviour are hardware-specific. The script cannot move a physical HDMI signal.

For the Ollama VM, use RDP, NoMachine, another virtual display, or a dummy plug if
Windows requires a display. Ollama compute itself does not need the monitor to be
connected to the RTX.

## Prerequisites

Before installing, confirm all of the following:

- The host firmware boots its display from the Ryzen iGPU.
- Qtile remains usable with the RTX bound to `vfio-pci`.
- `0000:01:00.0` is the RTX and `0000:01:00.1` is its audio function.
- The NVIDIA driver is installed on the Proxmox host for the running kernel.
- The Windows VM already passes through those functions successfully.
- Boot-time VFIO binding is already configured.
- The Windows VM has `onboot: 1` and working ACPI shutdown support.
- A second access path such as SSH is available for the first live test.

Capture the current evidence before changing anything:

```bash
./scripts/diagnostics/gpu-passthrough-report.sh > gpu-report.txt
qm list
qm config <VMID>
```

## Install

From the cloned repository, replace `<VMID>` with the Windows VM number:

```bash
sudo ./scripts/proxmox/install-gpu-passthrough-switch.sh \
  --vmid <VMID> \
  --user ramo
```

The installer defaults to the known RTX addresses. Override them only if
`lspci -nnk` shows that they changed:

```bash
sudo ./scripts/proxmox/install-gpu-passthrough-switch.sh \
  --vmid <VMID> \
  --user ramo \
  --gpu-pci 0000:01:00.0 \
  --audio-pci 0000:01:00.1
```

Deploy the updated Qtile config as the desktop user, then reload Qtile:

```bash
sudo apt-get install libnotify-bin
./setups/debian-qtile/install.sh --no-packages --skip-firefox
```

`libnotify-bin` supplies `notify-send`, which lets the background switch report a
failure through Dunst before any login-session restart.

The system installer creates a narrow passwordless sudo rule. It permits only a
read-only short status command and the fixed no-argument systemd toggle request;
it does not grant passwordless `qm`, `systemctl`, or an arbitrary shell.

## Power-state rule

`gpu-passthrough-guard.service` runs after the display manager and Proxmox guest
shutdown ordering, then returns the RTX to `vfio-pci` before reboot or poweroff.

`gpu-passthrough-sleep.service` is required by `sleep.target`. Before suspend,
hibernate, hybrid sleep, or suspend-then-hibernate, it gracefully stops the VM,
stops the X11 session, and binds the RTX to VFIO. After resume, it keeps VFIO,
starts the Windows VM, and restores the iGPU login screen.

The existing boot-time VFIO configuration remains the final authority at cold
boot, before Proxmox autostarts Windows.

## Verify

Check the current owner and guest state:

```bash
sudo gpu-passthrough-switch status
```

Inspect the last switch:

```bash
systemctl status gpu-passthrough-toggle.service
journalctl -u gpu-passthrough-toggle.service -b
```

In host mode, verify PRIME after logging back in:

```bash
nvidia-smi
xrandr --listproviders
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
  glxinfo -B
```

The RandR provider list should include `NVIDIA-G0`. If it does not, do not start
Steam yet; inspect the Xorg log and NVIDIA module state.

## Failure boundaries

Live device rebinding is less reliable than boot-time binding. A consumer GPU,
driver, firmware, or motherboard may fail to reset cleanly. Common safe failures
are:

- Windows ignores the ACPI shutdown request.
- Steam or another process still has the RTX open.
- `nvidia_drm` cannot unload.
- `nvidia-smi` cannot initialise the GPU after rebinding.
- Xorg does not create the PRIME provider until another session restart.

The script aborts instead of using `qm stop` or killing individual GPU clients.
If the GPU enters an unrecoverable state, rebooting restores the existing
boot-time VFIO path and the Windows autostart behaviour.

## Remove

Disable the power hooks before removing their files:

```bash
sudo systemctl disable --now \
  gpu-passthrough-guard.service \
  gpu-passthrough-sleep.service
```

Then remove the installed units, commands, configuration, and the dedicated
`/etc/sudoers.d/gpu-passthrough-switch` file, followed by:

```bash
sudo systemctl daemon-reload
```

The repository deliberately leaves bootloader, VFIO ID, VM, and NVIDIA package
rollback to the existing host-specific configuration.

## Primary references

- [Proxmox `qm(1)` manual](https://pve.proxmox.com/pve-docs/qm.1.html)
- [systemd sleep target ordering](https://www.freedesktop.org/software/systemd/man/latest/systemd.special.html#sleep.target)
- [NVIDIA PRIME Render Offload](https://download.nvidia.com/XFree86/Linux-x86_64/575.64/README/primerenderoffload.html)
- [NVIDIA RandR display offload](https://download.nvidia.com/XFree86/Linux-x86_64/575.64/README/randr14.html)
