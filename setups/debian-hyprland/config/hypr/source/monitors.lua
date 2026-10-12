-- The stable udev link is installed by install.sh. Do not add the detachable
-- NVIDIA card here: Hyprland must never hold it while the VM owns it.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})
