#!/usr/bin/env bash
# theme.sh: the WhiteSur look (vinceliuice) on KDE Plasma 6, WhiteSur light and dark only, from
# pinned local clones of upstream, each part with its removal.
#
#   theme.sh fetch                 clone or update the pinned upstream repositories into VENDOR
#                                  (default ~/Projects/vendor); the pins are below
#   theme.sh kde on|off            global themes, Plasma style, window decoration, colours and
#                                  wallpapers of WhiteSur and WhiteSur-dark (not the Liquid ones,
#                                  the Alt colours or the X11 scale copies of the decoration)
#   theme.sh icons on|off          WhiteSur, WhiteSur-light, WhiteSur-dark (the last two need the first)
#   theme.sh cursors on|off        WhiteSur-cursors
#   theme.sh gtk on|off            the prebuilt WhiteSur-Light and WhiteSur-Dark into ~/.themes
#                                  (no build tools, no theme-switcher program)
#   theme.sh kvantum on|off        Kvantum (Fedora package, asks sudo) with WhiteSur's theme; off,
#                                  widgets are Breeze
#   theme.sh apply light|dark|off  switch to WhiteSur (panels kept as they are), or off to KDE's
#                                  own look (Breeze)
#   theme.sh firefox on|off        the WhiteSur Firefox theme in your default profile, with its
#                                  prefs in a marked block of user.js; the profile's chrome folder
#                                  and user.js before are kept and put back by off. Firefox reads
#                                  both at its start only, so it may run meanwhile
#   theme.sh firefox-prefs on|off|diff  the operator's Firefox choices (firefox-prefs.js) in a marked
#                                  block of the default profile's user.js, or out of it; diff shows
#                                  each beside the value the profile has now
#   theme.sh autohide on|off       Firefox's toolbars hide until the pointer reaches the top
#                                  (MrOtherGuy's autohide_toolbox.css, MPL-2.0)
#   theme.sh others                every theme, icon set, cursor, colour scheme, window
#                                  decoration, switcher, widget and wallpaper outside WhiteSur: who
#                                  put it there (a package, KDE's Get New… with its registry entry,
#                                  this script) or nobody (left over); read-only
#   theme.sh others clean PATH...  archive those paths to ~/.local/state/theme-sh/others-<time>.tar.gz,
#                                  check the archive, then remove them (sudo for a path outside your
#                                  home); "--untracked" takes every left-over path others lists,
#                                  "--unused" every one of yours (store items too) the desktop does
#                                  not use now; a path in use is never taken. KDE's store registry
#                                  forgets the items whose files are gone (archived with them)
#   theme.sh others restore TAR    put an archive's paths back
#   theme.sh show                  what is installed and in use
#
# Run as yourself. The upstream install scripts run in a scratch home and only the WhiteSur parts
# are copied out, so nothing else lands in yours; every file copied is listed in
# ~/.local/state/theme-sh/<part>.list, which off removes exactly. Not done, on purpose: SDDM
# (Fedora 44 logs in with Plasma Login Manager), GDM, GTK's libadwaita override (one colour for
# every GTK 4 program), Flatpak runtimes, and the upstream removals (they delete KDE's own GTK 4
# files and leave Firefox's chrome folder behind).

set -euo pipefail
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
[[ $EUID != 0 ]] || die "run it as yourself (the themes and settings are yours)"

VENDOR=${VENDOR:-$HOME/Projects/vendor}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/theme-sh
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
CONF=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}

# Upstream, pinned (repository, commit, date of that commit).
PINS="WhiteSur-kde cf4df59ce91004f7ea39358b1b8ff917d5c329f7 2026-08-07
WhiteSur-icon-theme 73d8040da51a9ed74e47c7366e7e9ff437601a5c 2026-09-10
WhiteSur-cursors e190baf618ed95ee217d2fd45589bd309b37672b 2025-04-05
WhiteSur-gtk-theme d5782652d412137e26fb8ff55b55a5572e4c6995 2026-09-11
WhiteSur-firefox-theme ecc6465e2d30278a0f76604e622e3df8ac08ae1c 2026-08-11
firefox-csshacks 4869329f67522f17cd86bf504a552089d07261d5 2026-10-15"
url_of() { [[ $1 == firefox-csshacks ]] && echo https://github.com/MrOtherGuy/firefox-csshacks.git || echo "https://github.com/vinceliuice/$1.git"; }
repo() { local d=$VENDOR/$1; [[ -d $d/.git ]] || die "$1 is not fetched: theme.sh fetch"; echo "$d"; }

fetch() {
    local name sha day d try
    mkdir -p "$VENDOR"
    while read -r name sha day; do
        d=$VENDOR/$name
        [[ -d $d/.git ]] || git init -q "$d"
        git -C "$d" remote get-url origin >/dev/null 2>&1 || git -C "$d" remote add origin "$(url_of "$name")"
        if [[ $(git -C "$d" rev-parse -q --verify HEAD 2>/dev/null) != "$sha" ]]; then
            for try in 1 2 3 4 5; do
                git -C "$d" fetch -q --depth 1 origin "$sha" && break
                echo "$name: fetch failed (try $try), again in 10 s" >&2
                sleep 10
            done
            git -C "$d" checkout -q --detach "$sha" || die "$name: $sha could not be checked out"
        fi
        echo "$name at ${sha:0:12} ($day)"
    done <<<"$PINS"
}

# copy PART SRC DEST: copy a file or folder and note it for removal.
copy() {
    mkdir -p "$STATE" "$(dirname "$3")"
    rm -rf "$3"
    cp -a "$2" "$3"
    echo "$3" >>"$STATE/$1.list"
}
remove() {
    local p
    [[ -f $STATE/$1.list ]] || { echo "$1: nothing of ours installed"; return 0; }
    while IFS= read -r p; do
        case $p in "$HOME"/*) rm -rf "$p" ;; *) echo "skipped, outside home: $p" ;; esac
    done <"$STATE/$1.list"
    rm -f "$STATE/$1.list"
    echo "$1: removed"
}
# scratch PART REPO ARGS...: the upstream install script of REPO, run with a scratch home.
scratch() {
    local tmp=$1 dir=$2
    shift 2
    mkdir -p "$tmp/.config" "$tmp/.local/share"
    (cd "$dir" && HOME=$tmp XDG_DATA_HOME=$tmp/.local/share XDG_CONFIG_HOME=$tmp/.config ./install.sh "$@" >"$tmp/install.log" 2>&1) ||
        die "$dir/install.sh failed; see $tmp/install.log"
}

kde() {
    local tmp s
    case $1 in
    on)
        remove kde >/dev/null
        tmp=$(mktemp -d)
        scratch "$tmp" "$(repo WhiteSur-kde)" -c light dark -w default
        s=$tmp/.local/share
        for d in WhiteSur WhiteSur-dark; do
            copy kde "$s/aurorae/themes/$d" "$DATA/aurorae/themes/$d"
            copy kde "$s/plasma/desktoptheme/$d" "$DATA/plasma/desktoptheme/$d"
            copy kde "$s/plasma/look-and-feel/com.github.vinceliuice.$d" "$DATA/plasma/look-and-feel/com.github.vinceliuice.$d"
        done
        for d in WhiteSur.colors WhiteSurDark.colors; do copy kde "$s/color-schemes/$d" "$DATA/color-schemes/$d"; done
        for d in WhiteSur WhiteSur-light WhiteSur-dark; do [[ -d $s/wallpapers/$d ]] && copy kde "$s/wallpapers/$d" "$DATA/wallpapers/$d"; done
        cp -a "$tmp/.config/Kvantum/WhiteSur" "$STATE/kvantum-WhiteSur" 2>/dev/null || true
        rm -rf "$tmp"
        echo "kde: WhiteSur and WhiteSur-dark installed; theme.sh apply light|dark uses them"
        ;;
    off) remove kde; rm -rf "$STATE/kvantum-WhiteSur" ;;
    *) die "kde on|off" ;;
    esac
}
icons() {
    local tmp d
    case $1 in
    on)
        command -v gtk-update-icon-cache >/dev/null || die "gtk-update-icon-cache is missing: sudo dnf install gtk-update-icon-cache"
        remove icons >/dev/null
        tmp=$(mktemp -d)
        scratch "$tmp" "$(repo WhiteSur-icon-theme)"
        for d in WhiteSur WhiteSur-light WhiteSur-dark; do copy icons "$tmp/.local/share/icons/$d" "$DATA/icons/$d"; done
        rm -rf "$tmp"
        for d in WhiteSur WhiteSur-light WhiteSur-dark; do gtk-update-icon-cache -q "$DATA/icons/$d" 2>/dev/null || true; done
        echo "icons: WhiteSur, WhiteSur-light, WhiteSur-dark installed"
        ;;
    off) remove icons ;;
    *) die "icons on|off" ;;
    esac
}
cursors() {
    case $1 in
    on) remove cursors >/dev/null; copy cursors "$(repo WhiteSur-cursors)/dist" "$DATA/icons/WhiteSur-cursors"; echo "cursors: WhiteSur-cursors installed" ;;
    off) remove cursors ;;
    *) die "cursors on|off" ;;
    esac
}
gtk() {
    local tmp t
    case $1 in
    on)
        remove gtk >/dev/null
        tmp=$(mktemp -d)
        for t in Light Dark; do
            tar -xJf "$(repo WhiteSur-gtk-theme)/release/WhiteSur-$t.tar.xz" -C "$tmp"
            copy gtk "$tmp/WhiteSur-$t" "$HOME/.themes/WhiteSur-$t"
        done
        rm -rf "$tmp"
        echo "gtk: WhiteSur-Light and WhiteSur-Dark installed (prebuilt $(head -n 1 "$(repo WhiteSur-gtk-theme)/release/release-info.txt" 2>/dev/null))"
        ;;
    off) remove gtk ;;
    *) die "gtk on|off" ;;
    esac
}
kvantum() {
    case $1 in
    on)
        command -v kvantummanager >/dev/null || sudo dnf install -y kvantum
        [[ -d $STATE/kvantum-WhiteSur ]] || die "theme.sh kde on first (it brings WhiteSur's Kvantum theme)"
        remove kvantum >/dev/null
        copy kvantum "$STATE/kvantum-WhiteSur" "$CONF/Kvantum/WhiteSur"
        kvantummanager --set WhiteSur
        echo "kvantum: on; widgets follow it once theme.sh apply sets them (or now: theme.sh apply light|dark)"
        ;;
    off) remove kvantum; [[ -f $STATE/applied ]] && kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle Breeze; echo "kvantum: off (the package stays; sudo dnf remove kvantum)" ;;
    *) die "kvantum on|off" ;;
    esac
}

KEEP="KDE:LookAndFeelPackage KDE:widgetStyle General:ColorScheme Icons:Theme"
# GTK programs: KDE's GTK settings service if it answers, else the settings files it writes.
gtk_theme() {
    dbus-send --session --type=method_call --dest=org.kde.GtkConfig /GtkConfig org.kde.GtkConfig.setGtkTheme "string:$1" 2>/dev/null && return
    kwriteconfig6 --file gtk-3.0/settings.ini --group Settings --key gtk-theme-name "$1"
    kwriteconfig6 --file gtk-4.0/settings.ini --group Settings --key gtk-theme-name "$1"
}
kget() { kreadconfig6 --file "$1" --group "${2%%:*}" --key "${2#*:}" 2>/dev/null || true; }
apply() {
    local laf k
    case $1 in
    light) laf=com.github.vinceliuice.WhiteSur ;;
    dark) laf=com.github.vinceliuice.WhiteSur-dark ;;
    off)
        # KDE's own look, whatever was in use before (the operator, 18 Oct: only WhiteSur and
        # what KDE ships stay on this machine).
        plasma-apply-lookandfeel -a org.kde.breeze.desktop
        for k in $KEEP; do kwriteconfig6 --notify --file kdeglobals --group "${k%%:*}" --key "${k#*:}" --delete; done
        plasma-apply-cursortheme breeze_cursors >/dev/null
        gtk_theme Breeze
        rm -f "$STATE/applied"
        echo "apply: KDE's own look (Breeze)"
        return
        ;;
    *) die "apply light|dark|off" ;;
    esac
    [[ -d $DATA/plasma/look-and-feel/$laf ]] || die "WhiteSur is not installed: theme.sh kde on"
    mkdir -p "$STATE"
    if [[ ! -f $STATE/applied ]]; then
        for k in $KEEP; do printf '%s=%s\n' "$k" "$(kget kdeglobals "$k")"; done >"$STATE/applied"
        printf 'kcminputrc:Mouse:cursorTheme=%s\n' "$(kget kcminputrc Mouse:cursorTheme)" >>"$STATE/applied"
        printf 'gtk:theme=%s\n' "$(kreadconfig6 --file gtk-3.0/settings.ini --group Settings --key gtk-theme-name 2>/dev/null)" >>"$STATE/applied"
    fi
    # No --resetLayout: the theme's layout script would replace the panels with its own.
    plasma-apply-lookandfeel -a "$laf"
    # The global theme asks for Kvantum widgets; without Kvantum's theme they would fall back
    # to Qt's plain style, so they stay Breeze.
    if [[ ! -d $CONF/Kvantum/WhiteSur ]]; then kwriteconfig6 --notify --file kdeglobals --group KDE --key widgetStyle Breeze; fi
    if [[ -d $HOME/.themes/WhiteSur-Light ]]; then gtk_theme "$([[ $1 == dark ]] && echo WhiteSur-Dark || echo WhiteSur-Light)"; fi
    echo "apply: $laf (widgets $(kget kdeglobals KDE:widgetStyle), icons $(kget kdeglobals Icons:Theme), cursor $(kget kcminputrc Mouse:cursorTheme))"
}

# The default profile from profiles.ini (Firefox 147 and later may keep it under ~/.config).
profile() {
    local ini dir p
    for dir in "$HOME/.mozilla/firefox" "$CONF/mozilla/firefox"; do
        ini=$dir/profiles.ini
        [[ -f $ini ]] || continue
        p=$(awk -F= '/^\[Install/ {i=1} i && /^Default=/ {print $2; exit}' "$ini")
        [[ -n $p ]] || p=$(awk -F= '/^Path=/ {path=$2} /^Default=1/ {print path; exit}' "$ini")
        [[ -n $p ]] || continue
        [[ $p == /* ]] || p=$dir/$p
        [[ -d $p ]] && { echo "$p"; return; }
    done
    die "no Firefox profile found (start Firefox once)"
}
PREFS='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.drawInTitlebar", true);
user_pref("browser.uidensity", 0);
user_pref("layers.acceleration.force-enabled", true);
user_pref("mozilla.widget.use-argb-visuals", true);
user_pref("widget.gtk.rounded-bottom-corners.enabled", true);
user_pref("svg.context-properties.content.enabled", true);'
# Firefox reads chrome/ and user.js when it starts and never writes either (it writes prefs.js),
# so a change made while it runs shows at its next start.
when() { if pgrep -x firefox >/dev/null; then echo "; restart Firefox to see it"; else echo "; start Firefox"; fi; }
firefox() {
    local p src c
    p=$(profile)
    case $1 in
    on)
        src=$(repo WhiteSur-firefox-theme)/src
        if [[ ! -e $STATE/firefox-chrome.before && ! -e $STATE/firefox-chrome.none ]]; then
            mkdir -p "$STATE"
            if [[ -e $p/chrome ]]; then cp -aL "$p/chrome" "$STATE/firefox-chrome.before"; else touch "$STATE/firefox-chrome.none"; fi
        fi
        c=$p/chrome
        rm -rf "$c"
        mkdir -p "$c"
        cp -r "$src/WhiteSur" "$c/WhiteSur"
        cp -r "$src/common/icons" "$src/common/titlebuttons" "$src/common/pages" "$c/WhiteSur/"
        cp "$src"/common/*.css "$c/WhiteSur/"
        mkdir -p "$c/WhiteSur/parts" && cp "$src"/common/parts/*.css "$c/WhiteSur/parts/"
        cp "$src/userChrome-WhiteSur.css" "$c/userChrome.css"
        cp "$src/userContent-WhiteSur.css" "$c/userContent.css"
        cp "$src/customChrome.css" "$c/customChrome.css"
        sed -i '/^\/\/ linux-lab theme.sh begin$/,/^\/\/ linux-lab theme.sh end$/d' "$p/user.js" 2>/dev/null || true
        { echo '// linux-lab theme.sh begin'; echo "$PREFS"; echo '// linux-lab theme.sh end'; } >>"$p/user.js"
        echo "firefox: WhiteSur in $p (light and dark follow the system)$(when)"
        ;;
    off)
        rm -rf "$p/chrome"
        if [[ -e $STATE/firefox-chrome.before ]]; then mv "$STATE/firefox-chrome.before" "$p/chrome"; fi
        rm -f "$STATE/firefox-chrome.none"
        sed -i '/^\/\/ linux-lab theme.sh begin$/,/^\/\/ linux-lab theme.sh end$/d' "$p/user.js" 2>/dev/null || true
        [[ -s $p/user.js ]] || rm -f "$p/user.js"
        echo "firefox: the profile's chrome folder and user.js as before (prefs set while it ran stay in prefs.js)$(when)"
        ;;
    *) die "firefox on|off" ;;
    esac
}
# The operator's Firefox choices, beside the theme's block in user.js and as independent of it.
FF_PREFS=$(cd "$(dirname "$0")" && pwd)/firefox-prefs.js
firefox_prefs() {
    local p
    p=$(profile)
    [[ -f $FF_PREFS ]] || die "no $FF_PREFS"
    case $1 in
    on)
        sed -i '/^\/\/ linux-lab firefox-prefs begin$/,/^\/\/ linux-lab firefox-prefs end$/d' "$p/user.js" 2>/dev/null || true
        { echo '// linux-lab firefox-prefs begin'; grep '^user_pref(' "$FF_PREFS"; echo '// linux-lab firefox-prefs end'; } >>"$p/user.js"
        echo "firefox-prefs: $(grep -c '^user_pref(' "$FF_PREFS") prefs in $p/user.js$(when)"
        ;;
    off)
        sed -i '/^\/\/ linux-lab firefox-prefs begin$/,/^\/\/ linux-lab firefox-prefs end$/d' "$p/user.js" 2>/dev/null || true
        [[ -s $p/user.js ]] || rm -f "$p/user.js"
        echo "firefox-prefs: out of user.js (the values stay in prefs.js until changed)$(when)"
        ;;
    diff)
        python3 -I - "$FF_PREFS" "$p/prefs.js" <<'PY'
import re, sys
rx = re.compile(r'^user_pref\("([^"]+)",\s*(.*)\);\s*$', re.M)
want = rx.findall(open(sys.argv[1], encoding="utf-8").read())
try:
    have = dict(rx.findall(open(sys.argv[2], encoding="utf-8", errors="replace").read()))
except FileNotFoundError:
    have = {}
same = 0
for k, v in want:
    if have.get(k) == v:
        same += 1
    else:
        print(f"  {k}: {have.get(k, '(Firefox default)')} -> {v}")
print(f"{same} of {len(want)} as the profile has them now")
PY
        ;;
    *) die "firefox-prefs on|off|diff" ;;
    esac
}
autohide() {
    local p c
    p=$(profile)
    c=$p/chrome
    [[ -f $c/customChrome.css ]] || die "theme.sh firefox on first"
    case $1 in
    on)
        cp "$(repo firefox-csshacks)/chrome/autohide_toolbox.css" "$c/autohide_toolbox.css"
        grep -qxF '@import "autohide_toolbox.css";' "$c/customChrome.css" || sed -i '1i @import "autohide_toolbox.css";' "$c/customChrome.css"
        echo "autohide: on; the toolbars show when the pointer reaches the top$(when)"
        ;;
    off)
        sed -i '/^@import "autohide_toolbox.css";$/d' "$c/customChrome.css"
        rm -f "$c/autohide_toolbox.css"
        echo "autohide: off$(when)"
        ;;
    *) die "autohide on|off" ;;
    esac
}

# The folders where themes and their parts land, yours and the system's.
THEME_DIRS="plasma/look-and-feel plasma/desktoptheme plasma/layout-templates plasma/plasmoids aurorae/themes
color-schemes icons themes wallpapers kwin/tabbox kwin/scripts kwin/effects konsole Kvantum sddm/themes"
OTHERS_PY='
import os, re, shutil, subprocess, sys, xml.etree.ElementTree as ET
home, data, conf, state, dirs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5].split()
mode = sys.argv[6] if len(sys.argv) > 6 else "list"   # list, or untracked / unused: paths only, NUL-separated
ours = set()
for f in os.listdir(state) if os.path.isdir(state) else []:
    if f.endswith(".list"):
        ours.update(l.strip().rstrip("/") for l in open(os.path.join(state, f)) if l.strip())
kns = {}
reg = os.path.join(data, "knewstuff3")
for f in sorted(os.listdir(reg)) if os.path.isdir(reg) else []:
    if not f.endswith(".knsregistry"):
        continue
    try:
        root = ET.parse(os.path.join(reg, f)).getroot()
    except ET.ParseError:
        print("unreadable registry: " + os.path.join(reg, f), file=sys.stderr); continue
    for st in root.iter("stuff"):
        name = (st.findtext("name") or "?").strip()
        for i in st.iter("installedfile"):
            p = (i.text or "").strip()
            if p.endswith("/*"):
                p = p[:-2]
            if p:
                kns[p.rstrip("/")] = "%s (%s)" % (name, f[:-len(".knsregistry")])
# What the desktop uses now: names and paths from the settings that pick a theme part.
used, usedpaths = set(), []
for f in ("kdeglobals", "kwinrc", "kcminputrc", "plasmarc", "kscreenlockerrc", "plasma-org.kde.plasma.desktop-appletsrc",
          "gtk-3.0/settings.ini", "gtk-4.0/settings.ini", "Kvantum/kvantum.kvconfig", "konsolerc"):
    try:
        text = open(os.path.join(conf, f), errors="replace").read()
    except OSError:
        continue
    for k, v in re.findall(r"(?m)^([A-Za-z-]+(?:Enabled)?)\s*=\s*(.+)$", text):
        v = v.strip()
        if k in ("LookAndFeelPackage", "ColorScheme", "Theme", "theme", "cursorTheme", "name", "plugin", "LayoutName",
                 "gtk-theme-name", "gtk-icon-theme-name", "gtk-cursor-theme-name", "widgetStyle"):
            used.add(v.replace("__aurorae__svg__", ""))
        elif k.endswith("Enabled") and v == "true":
            used.add(k[:-len("Enabled")])
        for m in re.findall(r"(?:file://)?(/[^,;\n]+)", v):
            usedpaths.append(m)
def plugin_id(p):
    try:
        import json
        return json.load(open(os.path.join(p, "metadata.json")))["KPlugin"]["Id"]
    except Exception:
        return None
ournames = set(os.path.basename(x) for x in ours)
def in_use(p):
    n = os.path.basename(p)
    if n in ournames and p not in ours:
        return False  # a second copy of one theme.sh installed (the store WhiteSur cursors): ours is used
    for x in (n, os.path.splitext(n)[0], plugin_id(p)):
        if x and x in used:
            return True
    return any(u == p or u.startswith(p + "/") for u in usedpaths)
def owner(p):
    for q in [p] + [os.path.dirname(p)]:
        if q in ours:
            return "theme.sh", ""
        if q in kns:
            return "kde-store", kns[q]
    for k, v in kns.items():
        if k.startswith(p + "/"):
            return "kde-store", v
    return None, ""
def packaged(p):
    q = p
    if os.path.isdir(p):  # a folder a package fills is not always listed in it: ask for its first file
        for r, ds, fs in os.walk(p):  # (not a cache built on the machine, such as icon-theme.cache)
            fs = [f for f in fs if not f.endswith(".cache")]
            if fs:
                q = os.path.join(r, fs[0]); break
    return subprocess.run(["rpm", "-qf", "--quiet", q], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
roots = [(os.path.join(data, d), True) for d in dirs] + [(os.path.join(conf, "Kvantum"), True),
         (os.path.join(home, ".icons"), True), (os.path.join(home, ".themes"), True)]
if shutil.which("rpm"):
    roots += [(os.path.join("/usr/share", d), False) for d in dirs]
else:
    print("rpm missing: the system folders are not checked", file=sys.stderr)
seen = set()
for r, mine in roots:
    if r in seen or not os.path.isdir(r):
        continue
    seen.add(r)
    for e in sorted(os.listdir(r)):
        p = os.path.join(r, e)
        if r.endswith("/konsole") and (e.endswith((".profile", ".keytab")) or e == "linux-lab-tabs.css"):
            continue  # your Konsole profiles and keyboard layouts, and ux-fix.sh konsole-tabs
        if r.endswith("/Kvantum") and e == "kvantum.kvconfig":
            continue
        if mine:
            who, what = owner(p)
            if who == "theme.sh":
                continue
            who = who or "left-over"
        else:
            if packaged(p):
                continue
            who, what = "system-no-package", ""
        use = in_use(p)
        if mode == "inuse":
            if use:
                sys.stdout.write(p + "\0")
            continue
        if mode != "list":
            if mine and not use and (who == "left-over" or mode == "unused"):
                sys.stdout.write(p + "\0")
            continue
        size = subprocess.run(["du", "-sh", p], capture_output=True, text=True).stdout.split("\t")[0] or "?"
        print("%-17s %-6s %6s  %s%s" % (who, "IN-USE" if use else "", size, p, ("  [" + what + "]") if what else ""))
'
others_list() { python3 -c "$OTHERS_PY" "$HOME" "$DATA" "$CONF" "$STATE" "$THEME_DIRS" "$@"; }
# Drop from KDE store registries the items whose files are all gone, so Get New... no longer
# shows them as installed.
REGPRUNE_PY='
import os, sys, xml.etree.ElementTree as ET
gone = [p.rstrip("/") for p in sys.argv[2:]]
def removed(f):
    f = f.strip()
    f = f[:-2] if f.endswith("/*") else f
    f = f.rstrip("/")
    return any(f == g or f.startswith(g + "/") for g in gone)
for r in sorted(os.listdir(sys.argv[1])):
    if not r.endswith(".knsregistry"):
        continue
    path = os.path.join(sys.argv[1], r)
    tree = ET.parse(path); root = tree.getroot(); n = 0
    for st in list(root.findall("stuff")):
        files = [i.text or "" for i in st.iter("installedfile")]
        if files and all(removed(f) for f in files):
            root.remove(st); n += 1
    if n:
        body = ET.tostring(root, encoding="unicode")
        open(path, "w").write("<!DOCTYPE khotnewstuff3>\n" + body + "\n")  # as KNewStuff writes it
        print("%s: %d item(s) no longer installed" % (r, n))
'

others() {
    local a t list n inuse regs=() sudo=
    case ${1:-} in
    '')
        others_list
        echo "(theme.sh's own WhiteSur files and everything a package installed are not listed)"
        ;;
    clean)
        shift
        case ${1:-} in
        --untracked) mapfile -d '' -t list < <(others_list untracked) ;;
        --unused) mapfile -d '' -t list < <(others_list unused) ;;
        *) list=("$@") ;;
        esac
        ((${#list[@]})) || die "others clean PATH... (or --untracked, --unused); nothing to do"
        inuse=$(others_list inuse | tr '\0' '\n')
        for a in "${list[@]}"; do
            [[ $a == /* && -e $a ]] || die "not an absolute path that exists: $a"
            case $a in
            "$DATA"/* | "$CONF"/Kvantum/* | "$HOME"/.icons/* | "$HOME"/.themes/*) ;;
            /usr/share/*) sudo=sudo ;;
            *) die "not in a theme folder: $a" ;;
            esac
            ! grep -qxF "$a" <<<"$inuse" || die "in use by the desktop now, kept: $a"
        done
        [[ -d $DATA/knewstuff3 ]] && mapfile -t regs < <(find "$DATA/knewstuff3" -maxdepth 1 -name '*.knsregistry')
        mkdir -p "$STATE"
        t=$STATE/others-$(date +%Y%m%d-%H%M%S).tar.gz
        $sudo tar -cPzf "$t" "${list[@]}" "${regs[@]}"
        [[ -n $sudo ]] && sudo chown "$(id -u):$(id -g)" "$t"
        n=$(tar -tPzf "$t" | grep -c '' || true)
        for a in "${list[@]}"; do tar -tPzf "$t" "$a" >/dev/null 2>&1 || die "$a is not in $t; nothing removed"; done
        echo "archived: ${#list[@]} paths, $n entries, $(du -h "$t" | cut -f1) in $t"
        for a in "${list[@]}"; do $sudo rm -rf -- "$a" && echo "removed: $a"; done
        [[ ! -d $DATA/knewstuff3 ]] || python3 -c "$REGPRUNE_PY" "$DATA/knewstuff3" "${list[@]}"
        echo "back with: theme.sh others restore $t (the store registries as they were included)"
        ;;
    restore)
        [[ -f ${2:-} ]] || die "others restore ARCHIVE (one of $STATE/others-*.tar.gz)"
        if tar -tPzf "$2" | grep -q '^/usr/'; then sudo tar -xPzf "$2"; else tar -xPzf "$2"; fi
        echo "restored: $(tar -tPzf "$2" | grep -c '') entries from $2"
        ;;
    *) die "others [clean PATH...|--untracked|--unused | restore ARCHIVE]" ;;
    esac
}

show() {
    local part
    for part in kde icons cursors gtk kvantum; do
        echo "$part: $([[ -f $STATE/$part.list ]] && echo "installed ($(wc -l <"$STATE/$part.list") paths)" || echo "not installed")"
    done
    echo "applied: $(kget kdeglobals KDE:LookAndFeelPackage) (widgets $(kget kdeglobals KDE:widgetStyle), icons $(kget kdeglobals Icons:Theme), cursor $(kget kcminputrc Mouse:cursorTheme))"
    echo "firefox: $( (p=$(profile 2>/dev/null) && [[ -f $p/user.js ]] && grep -q 'linux-lab theme.sh begin' "$p/user.js" && echo on) || echo off)"
    echo "firefox-prefs: $( (p=$(profile 2>/dev/null) && [[ -f $p/user.js ]] && grep -q 'linux-lab firefox-prefs begin' "$p/user.js" && echo on) || echo off)"
}

case ${1:-} in
fetch) fetch ;;
kde | icons | cursors | gtk | kvantum | apply | firefox | autohide) "$1" "${2:-}" ;;
firefox-prefs) firefox_prefs "${2:-}" ;;
others) shift; others "$@" ;;
show) show ;;
*)
    echo "usage: $0 {fetch | kde|icons|cursors|gtk|kvantum|firefox|autohide on|off | firefox-prefs on|off|diff | apply light|dark|off | others [clean PATH...|--untracked|--unused | restore TAR] | show}" >&2
    exit 2
    ;;
esac
