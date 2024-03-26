read -p "Make sure you've deleted 'local-lvm' on proxmox web interface. Press any key to continue o Ctrl-C to quit"

lvremove /dev/pve/data
lvresize -l +100%FREE /dev/pve/root
resize2fs /dev/mapper/pve-root

echo "'local' storage has been resized"

pause