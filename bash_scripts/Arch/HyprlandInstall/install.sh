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

# Read Dependencies from file for AUR
DEPENDENCIES_FILE2="dependenciesAUR.txt"

if [ -f "$DEPENDENCIES_FILE2" ]; then
    mapfile -t dependenciesaur < "DEPENDENCIES_FILE2"
else
    echo "AUR Dependencies file not found!"
    exit 1
fi

# Install dependencies via paru
sudo paru -S --noconfirm "${dependenciesaur[@]}"

# Read Dependencies from file
DEPENDENCIES_FILE="dependencies.txt"

if [ -f "$DEPENDENCIES_FILE" ]; then
    mapfile -t dependencies < "DEPENDENCIES_FILE"
else
    echo "Dependencies file not found!"
    exit 1
fi

# Install dependencies via pacman
sudo pacman -S --noconfirm "${dependencies[@]}"

# Get custom dotfiles and move to .config
cd ~
git clone https://github.com/ramomolise/dotfiles.git
cd dotfiles
cp -r . ~/.config
cd ..
rm -rf dottfiles