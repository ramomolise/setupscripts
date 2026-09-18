local terminal = "foot"
local browser = "firefox-esr"
local files = "thunar"

local registered = {}

local function bind(keys, dispatcher, description, flags)
    assert(not registered[keys], "duplicate keybinding: " .. keys)
    registered[keys] = true
    local options = flags or {}
    options.description = description
    hl.bind(keys, dispatcher, options)
end

local function command(keys, value, description, flags)
    bind(keys, hl.dsp.exec_cmd(value), description, flags)
end

-- Dusky-inspired launch layer.
command("SUPER + Q", terminal, "Launch terminal")
command("SUPER + W", browser, "Launch browser")
command("SUPER + E", files, "Open file manager")
command("ALT + SPACE", "pkill rofi; rofi -show drun", "Application launcher")
command("CTRL + SHIFT + SPACE", "rm-keybinds", "Show keybindings")

-- Window and session controls.
bind("SUPER + C", hl.dsp.window.close(), "Close active window")
bind("SUPER + SHIFT + Q", hl.dsp.exit(), "Exit Hyprland")
bind("SUPER + A", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Toggle fullscreen")
bind("SUPER + D", hl.dsp.window.float({ action = "toggle" }), "Toggle floating")
bind("ALT + TAB", hl.dsp.window.cycle_next(), "Cycle windows")
command("SUPER + SHIFT + R", "hyprctl reload", "Reload Hyprland")

for _, direction in ipairs({
    { "LEFT", "l" }, { "DOWN", "d" }, { "UP", "u" }, { "RIGHT", "r" },
}) do
    bind("SUPER + " .. direction[1], hl.dsp.focus({ direction = direction[2] }), "Move focus", { repeating = true })
    bind("SUPER + SHIFT + " .. direction[1], hl.dsp.window.move({ direction = direction[2] }), "Move tiled window", { repeating = true })
end

for key = 1, 10 do
    local workspace = key == 10 and 10 or key
    local key_name = key == 10 and "0" or tostring(key)
    bind("SUPER + " .. key_name, hl.dsp.focus({ workspace = workspace }), "Switch to workspace " .. workspace)
    bind("SUPER + SHIFT + " .. key_name, hl.dsp.window.move({ workspace = workspace }), "Move window to workspace " .. workspace)
end

bind("SUPER + TAB", hl.dsp.focus({ workspace = "previous" }), "Switch to previous workspace")
bind("SUPER + mouse:272", hl.dsp.window.drag(), "Move floating window", { mouse = true })
bind("SUPER + mouse:273", hl.dsp.window.resize(), "Resize floating window", { mouse = true })

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
