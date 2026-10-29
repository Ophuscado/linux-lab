#!/usr/bin/env bash
# icc.sh: the TV's colour profile, the one macOS made for it, put in use on KDE.
#
#   icc.sh use [FILE] [OUTPUT]  copy FILE (default: icc/lg-tv-macos.icc beside this script) to
#                               ~/.local/share/icc/ and make KScreen use it on OUTPUT (default: the
#                               only output)
#   icc.sh show                 each output's profile and its source
#
# icc/lg-tv-macos.icc is macOS 15's display profile for the LG TV on this Mac ("LG TV SSCR2",
# /Library/ColorSync/Profiles/Displays, taken on 28 Oct 2026): the TV's EDID primaries, which are
# exactly BT.2020's, the sRGB tone curve on every channel, and an identity video-card gamma. Compared by
# eye on 29 Oct against the generated "wide gamut, gamma 2.2" profile used before, it looked right;
# that one is gone (KNOWLEDGE.md, Desktop).

set -euo pipefail
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ICC_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icc
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

output_of() {
    local o
    o=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$1 == "Output:" {print $3}')
    [[ $(wc -l <<<"$o") == 1 && -n $o ]] || die "name the output: $(tr '\n' ' ' <<<"$o")"
    echo "$o"
}

case ${1:-} in
use)
    src=${2:-$HERE/icc/lg-tv-macos.icc}
    [[ -f $src ]] || die "no profile $src"
    mkdir -p "$ICC_DIR"
    f=$ICC_DIR/$(basename "$src")
    [[ $(readlink -f "$src") == "$(readlink -f "$f" 2>/dev/null)" ]] || install -m 644 "$src" "$f"
    o=${3:-$(output_of)}
    kscreen-doctor "output.$o.iccprofile.$f" >/dev/null
    kscreen-doctor "output.$o.colorProfileSource.ICC" >/dev/null
    "$0" show
    ;;
show) kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^Output|ICC profile|Color profile source' ;;
*)
    echo "usage: $0 {use [FILE] [OUTPUT] | show}" >&2
    exit 2
    ;;
esac
