local terminal = "foot"
local browser = "firefox-esr"
local files = "thunar"

local function command(keys, value, description, flags)
    local options = flags or {}
    options.description = description
    hl.bind(keys, hl.dsp.exec_cmd(value), options)
end

-- Dusky-inspired launch layer.
command("SUPER + Q", terminal, "Launch terminal")
command("SUPER + W", browser, "Launch browser")
command("SUPER + E", files, "Open file manager")
command("ALT + SPACE", "pkill rofi; rofi -show drun", "Application launcher")
command("CTRL + SHIFT + SPACE", "rm-keybinds", "Show keybindings")

-- Window and session controls.
command("SUPER + C", "hyprctl dispatch killactive", "Close active window")
command("SUPER + SHIFT + Q", "hyprctl dispatch exit", "Exit Hyprland")
command("SUPER + F", "hyprctl dispatch fullscreen 1", "Toggle fullscreen")
command("SUPER + V", "hyprctl dispatch togglefloating", "Toggle floating")
command("SUPER + L", "hyprlock", "Lock session")
command("SUPER + SHIFT + R", "hyprctl reload", "Reload Hyprland")

for _, direction in ipairs({
    { "H", "l" }, { "J", "d" }, { "K", "u" }, { "L", "r" },
}) do
    command("SUPER + " .. direction[1], "hyprctl dispatch movefocus " .. direction[2], "Move focus")
    command("SUPER + SHIFT + " .. direction[1], "hyprctl dispatch movewindow " .. direction[2], "Move window")
end

for workspace = 1, 9 do
    command("SUPER + " .. workspace, "hyprctl dispatch workspace " .. workspace, "Switch workspace")
    command("SUPER + SHIFT + " .. workspace, "hyprctl dispatch movetoworkspace " .. workspace, "Move window to workspace")
end

-- Existing guarded passthrough workflow. Both actions fail closed when the
-- system component or NVIDIA driver is unavailable.
command("SUPER + SHIFT + G", [[sh -lc 'command -v gpu-passthrough-toggle >/dev/null && exec gpu-passthrough-toggle; notify-send -u critical "GPU switch unavailable" "Install the guarded GPU switch first."']], "Toggle RTX host/VM mode")
command("SUPER + G", [[sh -lc 'command -v steam-nvidia >/dev/null && exec steam-nvidia; notify-send -u critical "NVIDIA launcher unavailable" "Install the guarded GPU switch first."']], "Launch Steam on NVIDIA")

command("PRINT", [[sh -lc 'file="$HOME/Pictures/Screenshots/Screenshot-$(date +%Y%m%d-%H%M%S).png"; grim -g "$(slurp)" "$file" && notify-send "Screenshot saved" "$file"']], "Capture a region")
command("XF86AudioRaiseVolume", "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+", "Raise volume", { repeating = true })
command("XF86AudioLowerVolume", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", "Lower volume", { repeating = true })
command("XF86AudioMute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "Mute audio")
command("XF86MonBrightnessUp", "brightnessctl set +5%", "Raise brightness", { repeating = true })
command("XF86MonBrightnessDown", "brightnessctl set 5%-", "Lower brightness", { repeating = true })
