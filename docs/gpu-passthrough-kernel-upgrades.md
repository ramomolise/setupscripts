# GPU passthrough after a kernel upgrade

A passthrough GPU can only be handed to the Linux host when the NVIDIA module
stack exists for the kernel that is currently running. Installing a new kernel
without its matching headers can prevent DKMS from producing those modules.

## Check before switching to host mode

```bash
kernel=$(uname -r)
printf 'Running kernel: %s\n' "$kernel"
modinfo -k "$kernel" nvidia
modinfo -k "$kernel" nvidia_modeset
modinfo -k "$kernel" nvidia_drm
modinfo -k "$kernel" nvidia_uvm
dkms status
```

Do not continue if any module is unavailable. Install the header package for the
exact running kernel and rebuild the installed NVIDIA DKMS module first.

The GPU switch performs this same read-only preflight before it shuts down the
guest or changes PCI ownership. A failed preflight leaves the guest and VFIO
ownership unchanged.

## Failure after mutation begins

A bind can still fail for reasons that a module preflight cannot predict. If
host binding fails after the guest has stopped, the switch attempts a
fail-closed rollback:

1. Return both GPU functions to `vfio-pci`.
2. Confirm those bindings.
3. Start the guest.
4. Restore the display manager.
5. Return a failure status and retain the original error.

The rollback never force-stops a guest and never starts it before both VFIO
bindings succeed.

## Recover a mixed or unbound state

Use SSH or a real TTY because recovery may stop the graphical login session:

```bash
sudo gpu-passthrough-switch vm
sudo gpu-passthrough-switch status
```

The expected result is `Mode: vm`, both PCI functions on `vfio-pci`, and the
guest running. Do not start the guest manually while either function is owned
by a host driver or remains unbound.
