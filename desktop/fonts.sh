#!/usr/bin/env bash
# fonts.sh: Apple's San Francisco fonts and the closest open one (Inter), side by side, and
# which of them the desktop uses.
#
#   fonts.sh sf DMG...        install SF from Apple's disk images (SF-Pro.dmg, SF-Mono.dmg, ...,
#                             downloaded by you from https://developer.apple.com/fonts/) for
#                             you alone, in ~/.local/share/fonts/apple-sf
#   fonts.sh inter            install Inter (Fedora package rsms-inter-fonts; asks sudo)
#   fonts.sh use sf|inter     make it the desktop's font: KDE's general, menu, toolbar, small
#                             and window-title fonts, SF Mono or the open fallback for fixed
#                             width, and fontconfig's sans-serif (Firefox's pages, GTK)
#   fonts.sh use default      the fonts as they were before the first "use"
#   fonts.sh nerd [NAME]      a Nerd Font (default Hack: Hack Nerd Font and Hack Nerd Font Mono)
#                             from the latest Nerd Fonts release, for you alone, in
#                             ~/.local/share/fonts/nerd-NAME
#   fonts.sh konsole FAMILY [SIZE]|default   the font of your default Konsole profile (size 12),
#                             or the one it had before
#   fonts.sh show             what is installed and in use
#
# Apple's licence allows SF only for mock-ups of user interfaces for Apple platforms; using it
# as a Linux desktop font is outside it. The operator's choice, on their own Mac, 17 Oct 2026; the
# fonts never go into this repository or an image made from it.

set -euo pipefail
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
[[ $EUID != 0 ]] || die "run it as yourself (the fonts and settings are yours)"
DEST=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/apple-sf
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/fonts-sh
FC=${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d/60-linux-lab-fonts.conf
SIZE=${FONT_SIZE:-10}
KEYS="General:font General:menuFont General:toolBarFont General:smallestReadableFont General:fixed WM:activeFont"

family() { fc-list : family 2>/dev/null | tr ',' '\n' | grep -m1 -xF "$1" || true; }
qfont() { printf '%s,%s,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$1" "$2"; }
kget() { kreadconfig6 --file kdeglobals --group "${1%%:*}" --key "${1#*:}" 2>/dev/null || true; }
kset() { if [[ -n $2 ]]; then kwriteconfig6 --notify --file kdeglobals --group "${1%%:*}" --key "${1#*:}" "$2"; else kwriteconfig6 --notify --file kdeglobals --group "${1%%:*}" --key "${1#*:}" --delete; fi; }

sf() {
    local f n=0
    command -v 7z >/dev/null || die "7z is missing: sudo dnf install 7zip"
    [[ $# -gt 0 ]] || die "fonts.sh sf SF-Pro.dmg [SF-Mono.dmg ...]"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT # global on purpose: the trap runs after the function returns
    for f in "$@"; do
        [[ -f $f ]] || die "no such file: $f"
        7z x -y -o"$tmp/${f##*/}" "$f" >/dev/null
    done
    # A disk image holds a .pkg (a xar file); the .pkg a component folder also named *.pkg with a
    # Payload; the Payload a gzip'd cpio archive with the fonts. Only files are unpacked.
    for _ in 1 2 3; do
        while IFS= read -r -d '' f; do
            7z x -y -o"$f.x" "$f" >/dev/null 2>&1 || true
            mv "$f" "$f.done"
        done < <(find "$tmp" -type f \( -name '*.pkg' -o -name 'Payload' -o -name 'Payload~' \) ! -path '*.x/*.x/*.x/*.x/*' -print0)
    done
    mkdir -p "$DEST"
    while IFS= read -r -d '' f; do
        install -m 644 "$f" "$DEST/" && n=$((n + 1))
    done < <(find "$tmp" -type f \( -iname '*.otf' -o -iname '*.ttf' \) -print0)
    ((n > 0)) || die "no font found in $*"
    fc-cache -f "$DEST" >/dev/null
    echo "SF: $n font files in $DEST; families: $(fc-list : family file 2>/dev/null | grep -F "$DEST" | cut -d: -f2 | tr ',' '\n' | sed 's/^ *//' | sort -u | grep -E '^SF|^New York' | paste -sd, -)"
}

fontconfig_prefer() {
    mkdir -p "$(dirname "$FC")"
    cat >"$FC" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Written by linux-lab fonts.sh use; removed by fonts.sh use default. -->
<fontconfig>
  <alias><family>sans-serif</family><prefer><family>$1</family></prefer></alias>
  <alias><family>monospace</family><prefer><family>$2</family></prefer></alias>
</fontconfig>
EOF
    fc-cache >/dev/null 2>&1 || true
}

nerd() {
    local name=${1:-Hack} dest
    [[ $name =~ ^[A-Za-z0-9]+$ ]] || die "nerd NAME: a font of the Nerd Fonts release, e.g. Hack"
    dest=${XDG_DATA_HOME:-$HOME/.local/share}/fonts/nerd-$name
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL --retry 3 -o "$tmp/f.tar.xz" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.tar.xz" ||
        die "the download of $name.tar.xz from the Nerd Fonts release failed"
    mkdir -p "$dest"
    tar -xJf "$tmp/f.tar.xz" -C "$dest" --wildcards '*.ttf' '*.otf' 2>/dev/null || tar -xJf "$tmp/f.tar.xz" -C "$dest" --wildcards '*.ttf'
    fc-cache -f "$dest" >/dev/null
    echo "$name: $(find "$dest" -type f | grep -c .) files; families: $(fc-list : family file 2>/dev/null | grep -F "$dest" | cut -d: -f2 | tr ',' '\n' | sed 's/^ *//' | sort -u | paste -sd, -)"
}
konsole_font() {
    local prof f k=Appearance
    prof=$(kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile 2>/dev/null || true)
    f=${XDG_DATA_HOME:-$HOME/.local/share}/konsole/$prof
    [[ -n $prof && -f $f ]] || die "no default Konsole profile of yours (konsolerc [Desktop Entry] DefaultProfile)"
    mkdir -p "$STATE"
    if [[ $1 == default ]]; then
        [[ -f $STATE/konsole-font.before ]] || die "nothing to put back: fonts.sh konsole was not run"
        if [[ -s $STATE/konsole-font.before ]]; then kwriteconfig6 --file "$f" --group $k --key Font "$(cat "$STATE/konsole-font.before")"; else kwriteconfig6 --file "$f" --group $k --key Font --delete; fi
        rm -f "$STATE/konsole-font.before"
    else
        [[ -n $(family "$1") ]] || die "no font family '$1' installed (fonts.sh nerd Hack gives Hack Nerd Font Mono)"
        [[ -f $STATE/konsole-font.before ]] || kreadconfig6 --file "$f" --group $k --key Font >"$STATE/konsole-font.before" 2>/dev/null || true
        kwriteconfig6 --file "$f" --group $k --key Font "$(qfont "$1" "${2:-12}")"
    fi
    echo "konsole: profile $prof, font $(kreadconfig6 --file "$f" --group $k --key Font); new Konsole windows use it"
}

use() {
    local sans mono k
    # FONT_SANS and FONT_MONO name the families directly (tests, or another font).
    case $1 in
    sf)
        sans=${FONT_SANS:-$(family "SF Pro")}; [[ -n $sans ]] || sans=$(family "SF Pro Text")
        mono=${FONT_MONO:-$(family "SF Mono")}
        [[ -n $sans ]] || die "SF is not installed: fonts.sh sf SF-Pro.dmg SF-Mono.dmg"
        [[ -n $mono ]] || mono=$(family "Noto Sans Mono")
        ;;
    inter)
        sans=${FONT_SANS:-$(family "Inter")}; [[ -n $sans ]] || sans=$(family "Inter Variable")
        [[ -n $sans ]] || die "Inter is not installed: fonts.sh inter"
        mono=${FONT_MONO:-$(family "SF Mono")}; [[ -n $mono ]] || mono=$(family "Noto Sans Mono")
        ;;
    default)
        [[ -f $STATE/kdeglobals.before ]] || die "nothing to put back: fonts.sh use was not run"
        while IFS='=' read -r k v; do kset "$k" "$v"; done <"$STATE/kdeglobals.before"
        rm -f "$STATE/kdeglobals.before" "$FC"
        fc-cache >/dev/null 2>&1 || true
        echo "fonts: as before"
        return
        ;;
    *) die "fonts.sh use sf|inter|default" ;;
    esac
    mkdir -p "$STATE"
    if [[ ! -f $STATE/kdeglobals.before ]]; then
        for k in $KEYS; do printf '%s=%s\n' "$k" "$(kget "$k")"; done >"$STATE/kdeglobals.before"
    fi
    kset General:font "$(qfont "$sans" "$SIZE")"
    kset General:menuFont "$(qfont "$sans" "$SIZE")"
    kset General:toolBarFont "$(qfont "$sans" "$SIZE")"
    kset General:smallestReadableFont "$(qfont "$sans" $((SIZE - 2)))"
    kset WM:activeFont "$(qfont "$sans" "$SIZE")"
    kset General:fixed "$(qfont "${mono:-monospace}" "$SIZE")"
    fontconfig_prefer "$sans" "${mono:-monospace}"
    echo "fonts: $sans (size $SIZE), fixed ${mono:-monospace}; programs started from now on use them, Plasma at the next login"
}

case ${1:-} in
sf) shift; sf "$@" ;;
inter) sudo dnf install -y rsms-inter-fonts && fc-cache >/dev/null 2>&1; echo "Inter: $(family Inter)$(family 'Inter Variable')" ;;
use) use "${2:-}" ;;
nerd) nerd "${2:-}" ;;
konsole) [[ -n ${2:-} ]] || die "fonts.sh konsole FAMILY [SIZE] | default"; konsole_font "$2" "${3:-}" ;;
show)
    echo "installed: SF $(fc-list : family 2>/dev/null | grep -c '^SF' || true) families, Inter $([[ -n $(family Inter)$(family 'Inter Variable') ]] && echo yes || echo no)"
    for k in $KEYS; do echo "  $k = $(kget "$k")"; done
    echo "  fontconfig: $(fc-match sans-serif 2>/dev/null), $(fc-match monospace 2>/dev/null)"
    ;;
*)
    echo "usage: $0 {sf DMG... | inter | use sf|inter|default | nerd [NAME] | konsole FAMILY [SIZE]|default | show}" >&2
    exit 2
    ;;
esac
