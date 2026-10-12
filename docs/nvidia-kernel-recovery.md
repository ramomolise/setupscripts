# NVIDIA module recovery after a kernel upgrade

This helper addresses a narrow Debian/Proxmox failure: the system boots a new
kernel, but the matching headers were unavailable when NVIDIA DKMS ran. The
NVIDIA userspace tools remain installed, while `modprobe nvidia` and
`nvidia-smi` cannot communicate with the kernel driver.

The tool does not reinstall or upgrade the NVIDIA driver. It installs only the
exact running-kernel header package when needed and rebuilds the NVIDIA DKMS
version already registered on the machine.

## Diagnose first

```bash
./scripts/proxmox/repair-nvidia-dkms.sh
```

The report shows:

- the running kernel;
- the matching header package and header-tree state;
- the registered NVIDIA DKMS version;
- DKMS state for the running kernel; and
- module version and vermagic when available.

Diagnosis makes no changes. Exit status `0` means the module is already
available, `2` means the supported repair is needed, and `1` means the tool
cannot proceed safely.

If multiple NVIDIA DKMS versions are registered, select the intended installed
version explicitly:

```bash
./scripts/proxmox/repair-nvidia-dkms.sh \
  --module-version <VERSION>
```

## Apply the narrow repair

Review the diagnosis, then run:

```bash
sudo ./scripts/proxmox/repair-nvidia-dkms.sh --apply
```

The apply path:

1. Refuses to continue if `dpkg --audit` reports unfinished package work.
2. Resolves the exact running-kernel header package from configured APT data.
3. Installs that header package only when its build tree is missing.
4. Builds the already registered NVIDIA DKMS version for the running kernel.
5. Runs `depmod` and refreshes only that kernel's initramfs.
6. Verifies the resulting module version and vermagic.

The script never purges drivers, selects a new driver version, removes a
kernel, changes VFIO/IOMMU settings, rebinds a GPU, starts a VM, or reboots.

## After repair

If the GPU is assigned to VFIO, `nvidia-smi` will still be unable to inspect it;
that is expected. Verify PCI ownership before deciding whether a reboot or a
controlled passthrough handoff is required.

For the repository GPU switch, recover a mixed state from SSH or a real TTY:

```bash
sudo gpu-passthrough-switch vm
sudo gpu-passthrough-switch status
```

Do not start a passthrough guest manually until every GPU function it uses is
confirmed on `vfio-pci`.
