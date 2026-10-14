#!/usr/bin/env bash
# ux-fix.sh: Magic Mouse and middle-click paste on KDE (Wayland).
#
#   ux-fix.sh on [SPEED]   apply, now and after reboots
#   ux-fix.sh off          undo everything
#   ux-fix.sh show         what is in force
#
# What it changes and why (kernel source drivers/hid/hid-magicmouse.c, KWin source):
# - Middle click: the mouse driver guesses a middle button from one finger near the
#   centre of the surface (parameter emulate_3button, default on). Off, a click is left or
#   right only, like macOS.
# - Unwanted scrolls: the driver turns finger travel into wheel steps, one step per
#   (64 - scroll_speed) * 7 touch units. The default 32 needs 224 units, about a tenth of
#   the surface; a resting finger drifts that much. SPEED (default 10) raises it to 378
#   units: scrolling needs a deliberate swipe, and each swipe scrolls less. 0 to 63.
# - Middle-click paste: KWin offers the "primary selection" to every program; KDE 6.4 and
#   later can switch it off (kwinrc [Wayland] EnablePrimarySelection=false, read when the
#   session starts, so it takes a log out and in). Then nothing pastes on middle click.
#
# Not fixable here: the four-finger gestures of the trackpad need a longer swipe than
# three-finger ones; that threshold is fixed in KWin's code, not a setting.

set -euo pipefail

CONF=/etc/modprobe.d/hid_magicmouse.conf
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

kwin_key() { kwriteconfig6 --file kwinrc --group Wayland --key EnablePrimarySelection "$@"; }

show() {
    echo "mouse driver: $(cat /sys/module/hid_magicmouse/parameters/emulate_3button 2>/dev/null | sed 's/^[Y1]$/middle click emulated/; s/^[N0]$/no middle click/' || echo 'not loaded'), scroll_speed $(cat /sys/module/hid_magicmouse/parameters/scroll_speed 2>/dev/null || echo -)"
    echo "saved for next boots: $(cat $CONF 2>/dev/null || echo none)"
    echo "middle-click paste (KWin): EnablePrimarySelection=$(kreadconfig6 --file kwinrc --group Wayland --key EnablePrimarySelection --default true)"
    echo "kwin: $(kwin_wayland --version 2>/dev/null | head -n 1 || echo unknown); the paste setting needs 6.4 or later"
}

case ${1:-} in
on)
    speed=${2:-10}
    [[ $speed =~ ^[0-9]+$ && $speed -le 63 ]] || die "SPEED is 0 to 63"
    echo "options hid_magicmouse emulate_3button=0 scroll_speed=$speed" | sudo tee "$CONF" >/dev/null
    if [[ -d /sys/module/hid_magicmouse ]]; then
        echo 0 | sudo tee /sys/module/hid_magicmouse/parameters/emulate_3button >/dev/null
        echo "$speed" | sudo tee /sys/module/hid_magicmouse/parameters/scroll_speed >/dev/null
    else
        echo "the mouse driver is not loaded yet; the settings apply when the mouse connects"
    fi
    kwin_key --type bool false
    show
    echo "Log out and in once for the paste change; the mouse changes are live."
    ;;
off)
    sudo rm -f "$CONF"
    if [[ -d /sys/module/hid_magicmouse ]]; then
        echo 1 | sudo tee /sys/module/hid_magicmouse/parameters/emulate_3button >/dev/null
        echo 32 | sudo tee /sys/module/hid_magicmouse/parameters/scroll_speed >/dev/null
    fi
    kwin_key --delete
    show
    ;;
show) show ;;
*)
    echo "usage: $0 {on [SPEED] | off | show}" >&2
    exit 2
    ;;
esac
