#!/usr/bin/env bash
set -u

run_once() {
    local pattern=$1
    shift
    if ! pgrep -u "$UID" -f -- "$pattern" >/dev/null 2>&1; then
        "$@" &
    fi
}

run_once 'picom.*rm-architect' picom --config "$HOME/.config/picom/picom.conf" --log-file "$HOME/.local/state/rm-architect/picom.log"
run_once 'dunst' dunst --config "$HOME/.config/dunst/dunstrc"
run_once 'nm-applet' nm-applet --indicator

polkit_agent='/usr/lib/x86_64-linux-gnu/ukui-polkit/polkit-ukui-authentication-agent-1'
if [[ -x "$polkit_agent" ]]; then
    run_once 'polkit-ukui-authentication-agent-1' "$polkit_agent"
fi

wallpaper="$HOME/.local/share/backgrounds/rm-architect.png"
[[ -f "$wallpaper" ]] && feh --no-fehbg --bg-fill "$wallpaper"

xset r rate 250 35 >/dev/null 2>&1 || true
