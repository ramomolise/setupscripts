hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 12,
        border_size = 2,
        ["col.active_border"] = "rgba(8455b8ff) rgba(c7c4ceff) 45deg",
        ["col.inactive_border"] = "rgba(3b3944aa)",
        resize_on_border = true,
        layout = "dwindle",
    },
    decoration = {
        rounding = 12,
        active_opacity = 0.96,
        inactive_opacity = 0.90,
        blur = {
            enabled = true,
            size = 7,
            passes = 2,
            vibrancy = 0.15,
        },
        shadow = {
            enabled = true,
            range = 18,
            render_power = 3,
            color = "rgba(00000088)",
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        pseudotile = true,
        preserve_split = true,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        focus_on_activate = true,
    },
})
