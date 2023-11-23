#!/bin/bash

# Run command "cvt 1920 1080" but replace "1920 1080" with your own custom resolution
# Replace the information given by the command above
# Run "xrandr" command to get your display name, then replace "VGA-1" with your own display name

xrandr --newmode "1920x1080_60.00"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync
xrandr --addmode VGA-1 "1920x1080_60.00"
xrandr -s "1920x1080_60.00"
# xrandr --output VGA-1 --primary

# Time before launching browser | Allows Desktop Environment to Initialize

sleep 10

# Launch web browser in full screen mode

firefox --kiosk https://yourplexserver.com
