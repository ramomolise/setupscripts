#!/bin/bash

# Update and install rewuirements for script
sudo pacman -Syyu --noconfirm
sudo pacman -S --noconfirm base-devel git wget

if ! command -v paru &> /dev/null; then
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
    cd ..
    rm -rf paru
fi

# Install dependencies via paru
sudo paru -S --noconfirm hyprland hyprpaper hyprshot brillo waybar

# Install dependencies via pacman
sudo pacman -S --noconfirm pavucontrol networkmanager bluez bluez-utils acpi firefox

# Get custom dotfiles and move to .config
cd ~
git clone https://github.com/ramomolise/dotfiles.git
cd dotfiles
cp -r . ~/.config
cd ..
rm -rf dottfiles
