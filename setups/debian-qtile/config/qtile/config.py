import subprocess
from pathlib import Path

from libqtile import bar, hook, layout, widget
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy

mod = "mod4"
terminal = "alacritty"
home = Path.home()

palette = {
    "background": "09090d",
    "surface": "19171f",
    "surface_alt": "25222d",
    "text": "e8e6ec",
    "muted": "9995a2",
    "purple": "75429f",
    "purple_bright": "9a68c4",
    "silver": "c8c5ce",
    "warning": "e7ba6b",
}

keys = [
    Key([mod], "Return", lazy.spawn(terminal), desc="Open terminal"),
    Key([mod], "space", lazy.spawn("rofi -show drun"), desc="Open launcher"),
    Key([mod], "e", lazy.spawn("thunar"), desc="Open file manager"),
    Key([mod], "b", lazy.spawn("firefox-esr"), desc="Open browser"),
    Key([mod], "h", lazy.layout.left(), desc="Focus left"),
    Key([mod], "l", lazy.layout.right(), desc="Focus right"),
    Key([mod], "j", lazy.layout.down(), desc="Focus down"),
    Key([mod], "k", lazy.layout.up(), desc="Focus up"),
    Key([mod, "shift"], "h", lazy.layout.shuffle_left(), desc="Move left"),
    Key([mod, "shift"], "l", lazy.layout.shuffle_right(), desc="Move right"),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down(), desc="Move down"),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up(), desc="Move up"),
    Key([mod, "control"], "h", lazy.layout.grow_left(), desc="Grow left"),
    Key([mod, "control"], "l", lazy.layout.grow_right(), desc="Grow right"),
    Key([mod, "control"], "j", lazy.layout.grow_down(), desc="Grow down"),
    Key([mod, "control"], "k", lazy.layout.grow_up(), desc="Grow up"),
    Key([mod], "Tab", lazy.next_layout(), desc="Next layout"),
    Key([mod], "q", lazy.window.kill(), desc="Close window"),
    Key([mod], "f", lazy.window.toggle_fullscreen(), desc="Toggle fullscreen"),
    Key([mod], "v", lazy.window.toggle_floating(), desc="Toggle floating"),
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload Qtile"),
    Key([mod, "control", "shift"], "q", lazy.shutdown(), desc="Exit Qtile"),
    Key([], "Print", lazy.spawn("sh -c 'mkdir -p ~/Pictures/Screenshots && scrot ~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png'"), desc="Screenshot"),
    Key([], "XF86AudioRaiseVolume", lazy.spawn("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+")),
    Key([], "XF86AudioLowerVolume", lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")),
    Key([], "XF86AudioMute", lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")),
    Key([], "XF86MonBrightnessUp", lazy.spawn("brightnessctl set 5%+")),
    Key([], "XF86MonBrightnessDown", lazy.spawn("brightnessctl set 5%-")),
]

groups = [Group(str(number), label=str(number)) for number in range(1, 10)]
for group in groups:
    keys.extend(
        [
            Key([mod], group.name, lazy.group[group.name].toscreen(), desc=f"Go to group {group.name}"),
            Key([mod, "shift"], group.name, lazy.window.togroup(group.name), desc=f"Move to group {group.name}"),
        ]
    )

layout_theme = {
    "border_focus": palette["purple_bright"],
    "border_normal": palette["surface_alt"],
    "border_width": 2,
    "margin": 8,
}

layouts = [
    layout.Columns(**layout_theme),
    layout.MonadTall(**layout_theme),
    layout.Max(),
]

widget_defaults = {
    "font": "JetBrains Mono",
    "fontsize": 12,
    "padding": 8,
    "foreground": palette["text"],
    "background": palette["background"],
}
extension_defaults = widget_defaults.copy()


def separator():
    return widget.Sep(linewidth=0, padding=3, background=palette["background"])


top_bar = bar.Bar(
    [
        widget.TextBox(
            text="RM ARCHITECT",
            foreground=palette["purple_bright"],
            fontsize=13,
            padding=12,
        ),
        widget.GroupBox(
            active=palette["text"],
            inactive=palette["muted"],
            highlight_method="block",
            this_current_screen_border=palette["purple"],
            this_screen_border=palette["surface_alt"],
            other_current_screen_border=palette["silver"],
            urgent_border=palette["warning"],
            rounded=True,
            padding=6,
        ),
        separator(),
        widget.CurrentLayoutIcon(scale=0.55, foreground=palette["silver"]),
        widget.WindowName(foreground=palette["silver"], max_chars=70),
        widget.Systray(padding=7),
        widget.Net(format="NET {down}↓ {up}↑", foreground=palette["muted"], update_interval=3),
        widget.CPU(format="CPU {load_percent}%", foreground=palette["silver"], update_interval=3),
        widget.Memory(format="RAM {MemPercent}%", foreground=palette["silver"], update_interval=3),
        widget.Volume(fmt="VOL {}", foreground=palette["text"]),
        widget.Clock(format="%a %d %b  %H:%M", foreground=palette["purple_bright"]),
    ],
    34,
    background=palette["background"],
    border_color=palette["purple"],
    border_width=[0, 0, 1, 0],
    opacity=0.94,
)

screens = [Screen(top=top_bar)]

mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

floating_layout = layout.Floating(
    border_focus=palette["purple_bright"],
    border_normal=palette["surface_alt"],
    border_width=2,
    float_rules=[
        *layout.Floating.default_float_rules,
        Match(title="branchdialog"),
        Match(title="pinentry"),
        Match(wm_class="confirmreset"),
        Match(wm_class="makebranch"),
        Match(wm_class="ssh-askpass"),
        Match(wm_type="notification"),
    ],
)


@hook.subscribe.startup_once
def autostart():
    subprocess.Popen([str(home / ".config" / "qtile" / "autostart.sh")])


follow_mouse_focus = True
bring_front_click = False
cursor_warp = False
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True
auto_minimize = True
wmname = "LG3D"
