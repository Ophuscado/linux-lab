#!/usr/bin/env bash
# ux-fix.sh: the desktop the way the operator wants it on KDE Plasma 6 (Wayland), each change
# with its undo.
#
#   ux-fix.sh on [SPEED]          Magic Mouse and middle-click paste: apply, now and after reboots
#   ux-fix.sh off                 undo that
#   ux-fix.sh keyboard on|off     the ISO UK Magic Keyboard as on macOS, ~ and ñ included
#   ux-fix.sh launchers off|on    the global shortcuts that open programs: all off, or back
#   ux-fix.sh animations F|off    animations F times as long (0.5: twice as fast, 0: none)
#   ux-fix.sh borderless on|off   no title bar on maximized windows
#   ux-fix.sh solo on|off         KWin's own Minimize All script: Meta+Shift+O minimizes every
#                                 other window, Meta+Shift+D all of them
#   ux-fix.sh windows on [WxH]|off  new windows open centred; Konsole opens at WxH (default
#                                 1440x900) and every other normal window at 1366x860
#                                 (APP_SIZE), through KWin rules
#   ux-fix.sh edge-delay MS|off   how long the pointer has to push at a screen edge before an
#                                 auto-hidden panel shows (KWin's default 75 ms; default here 500)
#   ux-fix.sh konsole-keys on|off Shift+Alt+Up and Shift+Alt+Down in Konsole jump to the previous
#                                 and next command, as Cmd+Up/Down in Terminal.app
#   ux-fix.sh konsole-tabs on|off Konsole's tabs like its split-view headers: one flat bar, the
#                                 current tab in the window colour, the others on black, as wide
#                                 as the window shares
#   ux-fix.sh switcher on|off     Cmd+Tab's Thumbnail Grid without the tiles that vanish when a
#                                 window is closed from it (a fixed copy of KWin's own layout)
#   ux-fix.sh wheel on|off        the mouse wheel over a combo box, spin box or slider without the
#                                 keyboard focus scrolls the page instead of changing it (a style
#                                 BreezeNoWheel, Breeze with that one change, built from qt-nowheel/)
#   ux-fix.sh input on|off        pointer and keys as on macOS 15 (results/macos/macos-15): the
#                                 Magic Mouse flat at 0.875 (macOS: acceleration off, scaling
#                                 0.875; 43339 points for 49012 counts in its mouse-move log),
#                                 the trackpad flat, natural scrolling off, key repeat after
#                                 250 ms at 30 a second (hidutil: 250 ms, 33.3 ms); live
#   ux-fix.sh show                what is in force
#
# Run as yourself, not under sudo (the KDE settings are yours); the mouse part asks sudo itself.
#
# Mouse (kernel source drivers/hid/hid-magicmouse.c):
# - Middle click: the driver guesses a middle button from one finger near the centre of the
#   surface (emulate_3button, default on). Off, a click is left or right only, like macOS.
# - Unwanted scrolls: the driver turns finger travel into wheel steps, one per
#   (64 - scroll_speed) * 7 touch units. The default 32 needs 224 units, about a tenth of the
#   surface; a resting finger drifts that much. SPEED (default 10) raises it to 378 units. The
#   driver scrolls from a resting finger while the mouse moves whatever the speed; only a
#   driver change can stop that (on the board).
# - Why the setting did not hold after a reboot: the driver loads from the initramfs, which
#   does not have /etc/modprobe.d/hid_magicmouse.conf; a tmpfiles.d entry now sets the values
#   again once the system is up, and modprobe.d covers a later load.
# - Middle-click paste: KWin 6.4 and later can switch the primary selection off (kwinrc
#   [Wayland] EnablePrimarySelection=false), read at login.
# Keyboard: layout gb, variant mac ("English (UK, Macintosh)"), model applealu_iso; right Cmd
#   is the compose key: right Cmd, then ~, then n gives ñ (and ' e gives é, and so on). The
#   values before are kept and put back by off. KWin reloads the layout at once.
# Launchers: every .desktop file with X-KDE-Shortcuts (Meta+E for Dolphin, ...) gets _launch=none
#   in kglobalshortcutsrc; the file before is kept and put back by on. Takes a log out and in.
# Solo: the built-in script, not kwin-solo-window (see KNOWLEDGE.md); KWin loads or unloads it
#   on the reconfigure that follows, no log out.
# Windows: KWin has no default size for a window that does not ask for one, so the sizes are
#   rules applied when a window opens: Konsole (rule "linux-lab: Konsole size"), then every other
#   normal window ("linux-lab: window size"), so dialogs and utility windows keep theirs, and a
#   window with a fixed size stays as it is (KWin keeps its limits). Placement is kwinrc
#   [Windows] Placement=Centered.
# Edge delay: kwinrc [Windows] ElectricBorderDelay, read by every screen edge, so hot corners and
#   edge actions wait as long as the panel does.
# Konsole tabs: a style sheet in ~/.local/share/konsole/linux-lab-tabs.css named in konsolerc
#   [TabBar]; Konsole reads it at its start.
# Konsole keys: a keyboard layout ~/.local/share/konsole/linux-lab.keytab, Konsole's default one
#   (vendor/konsole-default.keytab) with two lines in front (its commands scrollPromptUp/Down,
#   not in full-screen programs such as vim or less), made the default profile's layout. The jump uses the prompt marks the shell writes (OSC 133; fish 4 writes them, INFERRED
#   from its release notes, not checked here). Cmd+Up/Down stay KWin's (tiling).
# Switcher: Plasma 6.7 ships one switcher layout, KWin's Thumbnail Grid ("Breeze" falls back to
#   it). Its grid fills the frame of a Plasma Dialog sized for N columns; the Dialog adds its
#   frame margins truncated to whole pixels and, once shown, takes them back unrounded, so the
#   grid gets N columns minus a pixel, lays out N-1 columns, and the row that spills is clipped:
#   after a close from the switcher only some tiles show, and Tab shows the others while those
#   go (lab_probe2 log, 18 Oct: a grid of 888 px became 887, 3 columns became 2). The copy
#   written here, ~/.local/share/kwin-wayland/tabbox/linux-lab-grid, sizes the grid by its own
#   columns and rows instead of the frame; it is made from the installed layout at each 'on',
#   so it follows Fedora's updates. off goes back to the layout set before.
# Wheel: Plasma 6.7 has no setting for it (KDE bug 399324, open since 2018; Qt only has a hint for
#   combo boxes). qt-nowheel/ is a Qt style that wraps Breeze and lets a control without the focus
#   pass the wheel to the page around it; a click or Tab gives it the focus, then the wheel changes
#   it as before. 'on' builds it (cmake, gcc-c++ and qt6-qtbase-devel from Fedora when missing),
#   installs it into Qt's own plugin folder (the one place every Qt program looks without a new
#   login) and makes it the widget style: running KDE programs switch at once. Programs written in
#   QML (System Settings' pages, Plasma itself) draw their controls another way and keep the wheel.
#   off puts the style before back and removes the plugin.
# Not settable in Plasma 6.7: four-finger gestures needing a longer swipe than three-finger ones.

set -euo pipefail

# Under sudo (settings.sh install or status), the KDE settings are still the desktop user's.
if [[ $EUID == 0 && -n ${SUDO_USER:-} && $SUDO_USER != root ]]; then
    exec runuser -u "$SUDO_USER" -- env HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)" "$0" "$@"
fi
CONF=/etc/modprobe.d/hid_magicmouse.conf
TMPF=/etc/tmpfiles.d/hid_magicmouse.conf
P=/sys/module/hid_magicmouse/parameters
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/ux-fix
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
[[ $EUID != 0 ]] || die "run it as yourself, or under sudo from your account (the KDE settings are yours)"

RULE=linux-lab-konsole-size
RULE2=linux-lab-app-size
APP_SIZE=${APP_SIZE:-1366x860}
# Every normal window opens at APP_SIZE (the operator, 18 Oct); APPS, a regex on the window
# class, narrows it to some programs.
APPS=${APPS:-}
TABS_CSS=${XDG_DATA_HOME:-$HOME/.local/share}/konsole/linux-lab-tabs.css
GRID_SRC=${UX_GRID_SRC:-/usr/share/kwin-wayland/tabbox/thumbnail_grid}
GRID=${XDG_DATA_HOME:-$HOME/.local/share}/kwin-wayland/tabbox/linux-lab-grid
HERE=$(cd "$(dirname "$0")" && pwd)
kwin_key() { kwriteconfig6 --file kwinrc --group Wayland --key EnablePrimarySelection "$@"; }
# KWin rereads its settings and loads or unloads scripts. dbus-send, since this Fedora has no
# qdbus6; every KWin change made here before 18 Oct was written without this call
# reaching KWin, so it waited for the next login.
kwin_reconfigure() {
    dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null ||
        echo "WARN: KWin did not answer the reconfigure; the change applies at the next login" >&2
}
kxkb() { kreadconfig6 --file kxkbrc --group Layout --key "$1" 2>/dev/null || true; }

show() {
    echo "mouse driver: $(sed 's/^[Y1]$/middle click emulated/; s/^[N0]$/no middle click/' $P/emulate_3button 2>/dev/null || echo 'not loaded'), scroll_speed $(cat $P/scroll_speed 2>/dev/null || echo -)"
    echo "saved for next boots: $(cat $CONF 2>/dev/null || echo none); after boot: $([[ -f $TMPF ]] && echo "$TMPF" || echo none)"
    echo "middle-click paste (KWin): EnablePrimarySelection=$(kreadconfig6 --file kwinrc --group Wayland --key EnablePrimarySelection --default true)"
    echo "keyboard: layout $(kxkb LayoutList) variant $(kxkb VariantList) model $(kxkb Model) options $(kxkb Options)"
    echo "launchers: $([[ -f $STATE/kglobalshortcutsrc.before ]] && echo off || echo as KDE ships them)"
    echo "animations: duration factor $(kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --default 1)"
    echo "borderless maximized: $(kreadconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows --default false)"
    echo "solo (Minimize All script): $(kreadconfig6 --file kwinrc --group Plugins --key minimizeallEnabled --default false)"
    echo "windows: placement $(kreadconfig6 --file kwinrc --group Windows --key Placement --default Smart), Konsole $(kreadconfig6 --file kwinrulesrc --group "$RULE" --key size --default 'as it asks'), other windows $(kreadconfig6 --file kwinrulesrc --group "$RULE2" --key size --default 'as they ask')"
    echo "edge delay: $(kreadconfig6 --file kwinrc --group Windows --key ElectricBorderDelay --default 75) ms"
    echo "konsole tabs: $(kreadconfig6 --file konsolerc --group TabBar --key TabBarUseUserStyleSheet --default false)"
    echo "switcher: $(kreadconfig6 --file kwinrc --group TabBox --key LayoutName --default thumbnail_grid)"
    echo "wheel: widget style $(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle --default Breeze), BreezeNoWheel $([[ -f $(nowheel_so) ]] && echo installed || echo 'not installed')"
}

# The settings input sets: kcminputrc group, key, value. KWin's own names for the devices.
MM='Libinput 76 803 Magic Mouse' TP='Libinput 76 613 Apple Inc. Magic Trackpad'
INPUT=("$MM|PointerAccelerationProfile|1" "$MM|PointerAcceleration|-0.125" "$MM|NaturalScroll|false"
    "$TP|PointerAccelerationProfile|1" "$TP|NaturalScroll|false" "Keyboard|RepeatDelay|250" "Keyboard|RepeatRate|30")
kin() { local g; read -ra g <<<"$1"; local a=(); for x in "${g[@]:0:3}"; do a+=(--group "$x"); done
    [[ ${#g[@]} -gt 3 ]] && a+=(--group "${1#* * * }"); kreadconfig6 --file kcminputrc "${a[@]}" --key "$2"; }
kout() { local g; read -ra g <<<"$1"; local a=(); for x in "${g[@]:0:3}"; do a+=(--group "$x"); done
    [[ ${#g[@]} -gt 3 ]] && a+=(--group "${1#* * * }"); kwriteconfig6 --notify --file kcminputrc "${a[@]}" --key "$2" "${@:3}"; }
# input_live: the running KWin takes the pointer settings now (it rereads kcminputrc only per device).
input_live() {
    local e n
    for e in $(busctl --user get-property org.kde.KWin /org/kde/KWin/InputDevice org.kde.KWin.InputDeviceManager devicesSysNames 2>/dev/null | grep -o '"event[0-9]*"' | tr -d '"'); do
        n=$(busctl --user get-property org.kde.KWin "/org/kde/KWin/InputDevice/$e" org.kde.KWin.InputDevice name | cut -d'"' -f2)
        local g; case $n in "Magic Mouse") g=$MM ;; "Apple Inc. Magic Trackpad") g=$TP ;; *) continue ;; esac
        busctl --user set-property org.kde.KWin "/org/kde/KWin/InputDevice/$e" org.kde.KWin.InputDevice pointerAccelerationProfileFlat b "$([[ $(kin "$g" PointerAccelerationProfile) == 1 ]] && echo true || echo false)"
        local acc nat; acc=$(kin "$g" PointerAcceleration); nat=$(kin "$g" NaturalScroll)
        busctl --user set-property org.kde.KWin "/org/kde/KWin/InputDevice/$e" org.kde.KWin.InputDevice pointerAcceleration d "${acc:-0}"
        busctl --user set-property org.kde.KWin "/org/kde/KWin/InputDevice/$e" org.kde.KWin.InputDevice naturalScroll b "${nat:-false}"
    done
}
input() {
    local i g k v
    mkdir -p "$STATE"
    case ${1:-} in
    on)
        [[ -f $STATE/kcminputrc.input.before ]] || for i in "${INPUT[@]}"; do IFS='|' read -r g k v <<<"$i"; echo "$g|$k|$(kin "$g" "$k")"; done >"$STATE/kcminputrc.input.before"
        for i in "${INPUT[@]}"; do IFS='|' read -r g k v <<<"$i"; kout "$g" "$k" "$v"; done
        ;;
    off)
        [[ -f $STATE/kcminputrc.input.before ]] || die "nothing to put back: input on was not run"
        while IFS='|' read -r g k v; do if [[ -n $v ]]; then kout "$g" "$k" "$v"; else kout "$g" "$k" --delete; fi; done <"$STATE/kcminputrc.input.before"
        rm -f "$STATE/kcminputrc.input.before"
        ;;
    *) die "input on|off" ;;
    esac
    input_live
    for i in "${INPUT[@]}"; do IFS='|' read -r g k v <<<"$i"; echo "${g#Libinput 76 [0-9]* } $k=$(kin "$g" "$k")"; done
}

# Where Qt loads styles from: its own plugin folder, as qtpaths6 reports it.
nowheel_so() { echo "$(qtpaths6 --query QT_INSTALL_PLUGINS 2>/dev/null || echo /usr/lib64/qt6/plugins)/styles/libbreezenowheel.so"; }
wheel() {
    local so b=$STATE/build-nowheel need=() p
    so=$(nowheel_so)
    case $1 in
    on)
        for p in cmake gcc-c++ qt6-qtbase-devel; do rpm -q "$p" >/dev/null 2>&1 || need+=("$p"); done
        ((${#need[@]} == 0)) || sudo dnf install -y "${need[@]}"
        mkdir -p "$STATE"
        cmake -S "$HERE/qt-nowheel" -B "$b" -DCMAKE_BUILD_TYPE=Release >/dev/null
        cmake --build "$b" -j"$(nproc)" >/dev/null
        sudo install -D -m 644 "$b/libbreezenowheel.so" "$so"
        [[ -f $STATE/widgetstyle.before ]] || kreadconfig6 --file kdeglobals --group KDE --key widgetStyle >"$STATE/widgetstyle.before" 2>/dev/null || true
        kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle BreezeNoWheel
        ;;
    off)
        [[ -f $STATE/widgetstyle.before ]] || die "nothing to put back: wheel on was not run"
        if [[ -s $STATE/widgetstyle.before ]]; then
            kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle "$(cat "$STATE/widgetstyle.before")"
        else
            kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle --delete
        fi
        sudo rm -f "$so"
        rm -rf "$b" "$STATE/widgetstyle.before"
        ;;
    *) die "wheel on|off" ;;
    esac
    echo "wheel: widget style $(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle --default Breeze), BreezeNoWheel $([[ -f $so ]] && echo installed || echo 'not installed')"
}

switcher() {
    local f=$GRID/contents/ui/main.qml
    case $1 in
    on)
        [[ -f $GRID_SRC/contents/ui/main.qml ]] || die "no $GRID_SRC to start from"
        mkdir -p "$STATE"
        [[ -f $STATE/switcher.before ]] || kreadconfig6 --file kwinrc --group TabBox --key LayoutName >"$STATE/switcher.before" 2>/dev/null || true
        rm -rf "$GRID"
        mkdir -p "${GRID%/*}"
        cp -r "$GRID_SRC" "$GRID"
        sed -i 's/"Id": "thumbnail_grid"/"Id": "linux-lab-grid"/; s/"Name": "Thumbnail Grid"/"Name": "Thumbnail Grid (linux-lab)"/' "$GRID/metadata.json"
        # The grid's own size, not the frame's; the same change as the one offered to KWin.
        if ! python3 - "$f" <<'PY'; then
import sys
p = sys.argv[1]
s = open(p).read()
for old, new in (
    ("                width: Math.min(Math.max(thumbnailGridView.cellWidth, optimalWidth), maxWidth)\n"
     "                height: Math.min(Math.max(thumbnailGridView.cellHeight, optimalHeight), maxHeight)\n",
     "                // The grid takes this size, not the frame's: once shown, the dialog may hand\n"
     "                // the main item back a pixel smaller, and the grid would drop a column\n"
     "                readonly property int gridWidth: Math.min(Math.max(thumbnailGridView.cellWidth, optimalWidth), maxWidth)\n"
     "                readonly property int gridHeight: Math.min(Math.max(thumbnailGridView.cellHeight, optimalHeight), maxHeight)\n"
     "                width: gridWidth\n"
     "                height: gridHeight\n"),
    ("                    id: thumbnailGridView\n"
     "                    anchors.fill: parent\n",
     "                    id: thumbnailGridView\n"
     "                    width: dialogMainItem.gridWidth\n"
     "                    height: dialogMainItem.gridHeight\n")):
    if s.count(old) != 1:
        sys.exit(1)
    s = s.replace(old, new)
open(p, "w").write(s)
PY
            rm -rf "$GRID"
            die "the installed Thumbnail Grid changed; the fix did not apply, nothing changed"
        fi
        kwriteconfig6 --file kwinrc --group TabBox --key LayoutName linux-lab-grid
        ;;
    off)
        [[ -f $STATE/switcher.before ]] || die "nothing to put back: switcher on was not run"
        if [[ -s $STATE/switcher.before ]]; then
            kwriteconfig6 --file kwinrc --group TabBox --key LayoutName "$(cat "$STATE/switcher.before")"
        else
            kwriteconfig6 --file kwinrc --group TabBox --key LayoutName --delete
        fi
        rm -rf "$GRID" "$STATE/switcher.before"
        rmdir --ignore-fail-on-non-empty "${GRID%/*}" "${GRID%/*/*}" 2>/dev/null || true
        ;;
    *) die "switcher on|off" ;;
    esac
    kwin_reconfigure
    echo "switcher: $(kreadconfig6 --file kwinrc --group TabBox --key LayoutName --default thumbnail_grid)"
}

mouse_on() {
    local speed=$1
    [[ $speed =~ ^[0-9]+$ && $speed -le 63 ]] || die "SPEED is 0 to 63"
    echo "options hid_magicmouse emulate_3button=0 scroll_speed=$speed" | sudo tee "$CONF" >/dev/null
    printf '%s\n' "# Written by ux-fix.sh on; removed by ux-fix.sh off." \
        "w $P/emulate_3button - - - - 0" "w $P/scroll_speed - - - - $speed" | sudo tee "$TMPF" >/dev/null
    if [[ -d $P ]]; then
        echo 0 | sudo tee $P/emulate_3button >/dev/null
        echo "$speed" | sudo tee $P/scroll_speed >/dev/null
    else
        echo "the mouse driver is not loaded yet; the settings apply when the mouse connects"
    fi
    # The lab's driver (kernel/magicmouse.sh, beside a built-in one) takes the same settings.
    local lp=/sys/module/hid_magicmouse_lab/parameters lo=/etc/modprobe.d/hid_magicmouse-lab.conf
    if [[ -d $lp ]]; then
        echo 0 | sudo tee $lp/emulate_3button >/dev/null
        echo "$speed" | sudo tee $lp/scroll_speed >/dev/null
    fi
    if [[ -f $lo ]]; then sudo sed -i -E "s/emulate_3button=[0-9YN]+/emulate_3button=0/; s/scroll_speed=[0-9]+/scroll_speed=$speed/" "$lo"; fi
}
mouse_off() {
    sudo rm -f "$CONF" "$TMPF"
    if [[ -d $P ]]; then
        echo 1 | sudo tee $P/emulate_3button >/dev/null
        echo 32 | sudo tee $P/scroll_speed >/dev/null
    fi
}

keyboard() {
    local k
    case $1 in
    on)
        mkdir -p "$STATE"
        if [[ ! -f $STATE/kxkbrc.before ]]; then
            for k in Use LayoutList VariantList Model Options ResetOldOptions; do printf '%s=%s\n' "$k" "$(kxkb $k)"; done >"$STATE/kxkbrc.before"
        fi
        kwriteconfig6 --file kxkbrc --group Layout --key Use --type bool true
        kwriteconfig6 --file kxkbrc --group Layout --key LayoutList gb
        kwriteconfig6 --file kxkbrc --group Layout --key VariantList mac
        kwriteconfig6 --file kxkbrc --group Layout --key Model applealu_iso
        kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions --type bool true
        kwriteconfig6 --file kxkbrc --group Layout --key Options compose:rwin
        ;;
    off)
        [[ -f $STATE/kxkbrc.before ]] || die "nothing to put back: keyboard on was not run"
        while IFS='=' read -r k v; do
            if [[ -n $v ]]; then kwriteconfig6 --file kxkbrc --group Layout --key "$k" "$v"; else kwriteconfig6 --file kxkbrc --group Layout --key "$k" --delete; fi
        done <"$STATE/kxkbrc.before"
        rm -f "$STATE/kxkbrc.before"
        ;;
    *) die "keyboard on|off" ;;
    esac
    dbus-send --session --type=signal /Layouts org.kde.keyboard.reloadConfig 2>/dev/null || true
    echo "keyboard: layout $(kxkb LayoutList) variant $(kxkb VariantList) model $(kxkb Model) options $(kxkb Options)"
}

launchers() {
    local f rc=${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc n=0
    case $1 in
    off)
        mkdir -p "$STATE"
        [[ -f $STATE/kglobalshortcutsrc.before ]] || cp -p "$rc" "$STATE/kglobalshortcutsrc.before" 2>/dev/null || : >"$STATE/kglobalshortcutsrc.before"
        for f in /usr/share/applications/*.desktop "${XDG_DATA_HOME:-$HOME/.local/share}"/applications/*.desktop; do
            [[ -f $f ]] && grep -q '^X-KDE-Shortcuts=..*' "$f" || continue
            kwriteconfig6 --file kglobalshortcutsrc --group services --group "${f##*/}" --key _launch none
            n=$((n + 1))
        done
        echo "launchers: $n program shortcuts off; log out and in once"
        ;;
    on)
        [[ -f $STATE/kglobalshortcutsrc.before ]] || die "nothing to put back: launchers off was not run"
        if [[ -s $STATE/kglobalshortcutsrc.before ]]; then cp -p "$STATE/kglobalshortcutsrc.before" "$rc"; else rm -f "$rc"; fi
        rm -f "$STATE/kglobalshortcutsrc.before"
        echo "launchers: the shortcuts as before; log out and in once"
        ;;
    *) die "launchers off|on" ;;
    esac
}

rules_list() { kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true; }
rules_set() {
    kwriteconfig6 --file kwinrulesrc --group General --key rules "$1"
    kwriteconfig6 --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<<"$1" | grep -c . || true)"
}
windows() {
    local size=${2:-1440x900} k rules
    case $1 in
    on)
        [[ $size =~ ^[0-9]+x[0-9]+$ ]] || die "windows on WxH, e.g. 1440x900"
        kwriteconfig6 --file kwinrc --group Windows --key Placement Centered
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key Description "linux-lab: Konsole size"
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key wmclass konsole
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key wmclassmatch 2
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key types 1
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key size "${size/x/,}"
        kwriteconfig6 --file kwinrulesrc --group "$RULE" --key sizerule 3
        kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key Description "linux-lab: window size"
        if [[ -n $APPS ]]; then
            kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key wmclass "$APPS"
            kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key wmclassmatch 3
        else
            kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key wmclass --delete
            kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key wmclassmatch --delete
        fi
        kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key types 1
        kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key size "${APP_SIZE/x/,}"
        kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key sizerule 3
        rules=$(rules_list | tr ',' '\n' | grep -vxF -e "$RULE" -e "$RULE2" | paste -sd, - || true)
        rules_set "${rules:+$rules,}$RULE,$RULE2"
        ;;
    off)
        kwriteconfig6 --file kwinrc --group Windows --key Placement --delete
        for k in Description wmclass wmclassmatch types size sizerule; do
            kwriteconfig6 --file kwinrulesrc --group "$RULE" --key "$k" --delete
            kwriteconfig6 --file kwinrulesrc --group "$RULE2" --key "$k" --delete
        done
        rules=$(rules_list | tr ',' '\n' | grep -vxF -e "$RULE" -e "$RULE2" | paste -sd, - || true)
        rules_set "$rules"
        ;;
    *) die "windows on [WxH] | off" ;;
    esac
    kwin_reconfigure
    echo "windows: placement $(kreadconfig6 --file kwinrc --group Windows --key Placement --default Smart), Konsole $(kreadconfig6 --file kwinrulesrc --group "$RULE" --key size --default 'as it asks'), other windows $(kreadconfig6 --file kwinrulesrc --group "$RULE2" --key size --default 'as they ask')"
}
KEYTAB=${XDG_DATA_HOME:-$HOME/.local/share}/konsole/linux-lab.keytab
konsole_keys() {
    local base prof f
    # Konsole builds its layouts into the program (no /usr/share/konsole/default.keytab),
    # so the lab keeps a copy of its default one.
    base=${KONSOLE_KEYTAB_BASE:-/usr/share/konsole/default.keytab}
    [[ -r $base ]] || base=$(cd "$(dirname "$0")" && pwd)/konsole-default.keytab
    prof=$(kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile 2>/dev/null || true)
    f=${XDG_DATA_HOME:-$HOME/.local/share}/konsole/$prof
    [[ -n $prof && -f $f ]] || die "no default Konsole profile of yours (konsolerc [Desktop Entry] DefaultProfile)"
    case $1 in
    on)
        [[ -r $base ]] || die "no $base to start from"
        mkdir -p "$STATE"
        [[ -f $STATE/konsole-keys.before ]] || kreadconfig6 --file "$f" --group Keyboard --key KeyBindings >"$STATE/konsole-keys.before" 2>/dev/null || true
        {
            echo '# Written by linux-lab ux-fix.sh konsole-keys on: Konsole'"'"'s default layout with the jump'
            echo '# to the previous and next command in front.'
            echo 'keyboard "linux-lab"'
            echo 'key Up+Shift+Alt-AppScreen : scrollPromptUp'
            echo 'key Down+Shift+Alt-AppScreen : scrollPromptDown'
            grep -v '^keyboard ' "$base"
        } >"$KEYTAB"
        kwriteconfig6 --file "$f" --group Keyboard --key KeyBindings linux-lab
        ;;
    off)
        [[ -f $STATE/konsole-keys.before ]] || die "nothing to put back: konsole-keys on was not run"
        if [[ -s $STATE/konsole-keys.before ]]; then kwriteconfig6 --file "$f" --group Keyboard --key KeyBindings "$(cat "$STATE/konsole-keys.before")"; else kwriteconfig6 --file "$f" --group Keyboard --key KeyBindings --delete; fi
        rm -f "$STATE/konsole-keys.before" "$KEYTAB"
        ;;
    *) die "konsole-keys on|off" ;;
    esac
    echo "konsole keys: profile $prof, layout $(kreadconfig6 --file "$f" --group Keyboard --key KeyBindings --default default); new Konsole windows use it"
}
konsole_tabs() {
    local k
    case $1 in
    on)
        mkdir -p "$STATE" "$(dirname "$TABS_CSS")"
        if [[ ! -f $STATE/konsolerc.tabbar.before ]]; then
            for k in TabBarUseUserStyleSheet TabBarUserStyleSheetFile ExpandTabWidth; do
                printf '%s=%s\n' "$k" "$(kreadconfig6 --file konsolerc --group TabBar --key "$k" 2>/dev/null || true)"
            done >"$STATE/konsolerc.tabbar.before"
        fi
        cat >"$TABS_CSS" <<'EOF'
/* Written by linux-lab ux-fix.sh konsole-tabs on; removed by konsole-tabs off.
   Tabs drawn like Konsole's split-view headers: flat, the title in the window font, the
   current one in the window colour, the others on the terminal black. */
QTabBar { background: #000000; }
QTabBar::tab {
    background: #000000;
    color: palette(placeholder-text);
    border: none;
    margin: 0;
    padding: 4px 12px;
    min-width: 8em;
}
QTabBar::tab:selected { background: palette(window); color: palette(window-text); }
QTabBar::tab:hover:!selected { color: palette(window-text); }
QTabWidget::pane { border: none; }
EOF
        kwriteconfig6 --file konsolerc --group TabBar --key TabBarUseUserStyleSheet --type bool true
        kwriteconfig6 --file konsolerc --group TabBar --key TabBarUserStyleSheetFile "file://$TABS_CSS"
        kwriteconfig6 --file konsolerc --group TabBar --key ExpandTabWidth --type bool true
        ;;
    off)
        [[ -f $STATE/konsolerc.tabbar.before ]] || die "nothing to put back: konsole-tabs on was not run"
        while IFS='=' read -r k v; do
            if [[ -n $v ]]; then kwriteconfig6 --file konsolerc --group TabBar --key "$k" "$v"; else kwriteconfig6 --file konsolerc --group TabBar --key "$k" --delete; fi
        done <"$STATE/konsolerc.tabbar.before"
        rm -f "$STATE/konsolerc.tabbar.before" "$TABS_CSS"
        ;;
    *) die "konsole-tabs on|off" ;;
    esac
    echo "konsole tabs: $(kreadconfig6 --file konsolerc --group TabBar --key TabBarUseUserStyleSheet --default false); new Konsole windows show it"
}

case ${1:-} in
on)
    mouse_on "${2:-10}"
    kwin_key --type bool false
    show
    echo "Log out and in once for the paste change; the mouse changes are live."
    ;;
off)
    mouse_off
    kwin_key --delete
    show
    ;;
keyboard) keyboard "${2:-}" ;;
input) input "${2:-}" ;;
launchers) launchers "${2:-}" ;;
animations)
    case ${2:-} in
    off) kwriteconfig6 --notify --file kdeglobals --group KDE --key AnimationDurationFactor --delete ;;
    '' | *[!0-9.]*) die "animations FACTOR (0 to 1, e.g. 0.5) or animations off" ;;
    *) kwriteconfig6 --notify --file kdeglobals --group KDE --key AnimationDurationFactor "$2" ;;
    esac
    kwin_reconfigure
    echo "animations: duration factor $(kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --default 1)"
    ;;
borderless)
    case ${2:-} in
    on) kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows --type bool true ;;
    off) kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows --delete ;;
    *) die "borderless on|off" ;;
    esac
    kwin_reconfigure
    echo "borderless maximized: $(kreadconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows --default false)"
    ;;
solo)
    case ${2:-} in
    on) kwriteconfig6 --file kwinrc --group Plugins --key minimizeallEnabled --type bool true ;;
    off) kwriteconfig6 --file kwinrc --group Plugins --key minimizeallEnabled --delete ;;
    *) die "solo on|off" ;;
    esac
    kwin_reconfigure
    echo "solo (Minimize All script): $(kreadconfig6 --file kwinrc --group Plugins --key minimizeallEnabled --default false)"
    ;;
windows) windows "${2:-}" "${3:-}" ;;
edge-delay)
    case ${2:-500} in
    off) kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderDelay --delete ;;
    *[!0-9]*) die "edge-delay MS (e.g. 500) or edge-delay off" ;;
    *) kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderDelay "${2:-500}" ;;
    esac
    kwin_reconfigure
    echo "edge delay: $(kreadconfig6 --file kwinrc --group Windows --key ElectricBorderDelay --default 75) ms"
    ;;
konsole-tabs) konsole_tabs "${2:-}" ;;
konsole-keys) konsole_keys "${2:-}" ;;
switcher) switcher "${2:-}" ;;
wheel) wheel "${2:-}" ;;
show) show ;;
*)
    echo "usage: $0 {on [SPEED] | off | keyboard on|off | input on|off | launchers off|on | animations F|off | borderless on|off | solo on|off | windows on [WxH]|off | edge-delay MS|off | konsole-tabs on|off | konsole-keys on|off | switcher on|off | wheel on|off | show}" >&2
    exit 2
    ;;
esac
