#!/bin/bash

############################################# Custom Resolution Fix for X11 #############################################

# Run command "cvt 1920 1080" but replace "1920 1080" with your own custom resolution

cvt 1920 1080

# Replace the Modeline information on the command below with the information given by the previous command above

xrandr --newmode "1920x1080_60.00"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync

# Run "xrandr" command to get your display name, then replace "VGA-1" with your own display name
# Also replace "1920x1080_60.00" with your given resolution

xrandr --addmode VGA-1 "1920x1080_60.00"
xrandr --output VGA-1 --mode "1920x1080_60.00"

#########################################################################################################################
