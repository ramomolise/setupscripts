# GPU passthrough workflow

GPU passthrough is hardware- and firmware-specific. This repository deliberately
starts with read-only evidence instead of automatically editing bootloader or
VFIO configuration.

## 1. Capture the host state

```bash
./scripts/diagnostics/gpu-passthrough-report.sh > gpu-report.txt
```

Run it once normally and again with `sudo` if kernel messages are restricted.
Review the report before sharing it because PCI topology identifies hardware.

## 2. Confirm prerequisites

- IOMMU/AMD-Vi or VT-d enabled in firmware.
- GPU and its companion audio function identified by PCI ID.
- Viable IOMMU grouping for every function being passed through.
- A separate display path for the host, or a tested remote-management path.
- VM configuration and host boot files backed up.

## 3. Change one layer at a time

1. Enable IOMMU kernel parameters and reboot.
2. Re-run the report and confirm groups.
3. Bind the exact target PCI functions to VFIO and reboot.
4. Add those functions to the VM with no competing emulated display when
   appropriate.
5. Install guest drivers only after the device is stable with a basic driver.

If a Windows guest goes black when the NVIDIA driver loads but the same device
works in a Linux guest, preserve host logs and compare reset behaviour before
changing unrelated VM graphics settings.

Never paste an unreviewed VM configuration over another machine: PCI addresses,
ROM requirements, IOMMU groups, and primary-GPU behaviour differ.
