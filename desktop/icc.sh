#!/usr/bin/env bash
# icc.sh: the display's colour profile, made here and put in use, with no vendor name in it.
#
#   icc.sh make [NITS] [FILE]   write the profile (default 2000 nits, FILE default
#                               ~/.local/share/icc/wide-gamut-2.2-<NITS>nits.icc)
#   icc.sh use FILE [OUTPUT]    make KScreen use FILE on OUTPUT (default: the only output)
#   icc.sh show                 each output's profile and its source
#
# The profile is the one oled-tv-calibrator writes as "Native HDR" (MIT, read on 17 Oct 2026,
# see KNOWLEDGE.md), the same for every TV whatever model name it carries: primaries between
# sRGB's and P3's (x,y 0.670,0.312 / 0.273,0.659 / 0.153,0.045), a D65 white with an identity
# adaptation tag (so KWin takes D50), a gamma 2.2 curve, an identity MHC2 tag and the peak in
# lumi. KWin then maps sRGB into that wider gamut, which tones colours down on this TV; the
# owner prefers it to KScreen's Built-in profile and to none. Only the texts differ from
# the calibrator's file: its description and copyright name a TV model and the program.

set -euo pipefail
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
ICC_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icc
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

MAKE_PY='
import struct, sys, time
nits, out = float(sys.argv[1]), sys.argv[2]
def u32(v): return struct.pack(">I", v)
def s15(v): return struct.pack(">i", int(round(v * 65536)))
def pad(b): return b + b"\0" * (-len(b) % 4)
def xyz(x, y, z): return b"XYZ " + u32(0) + s15(x) + s15(y) + s15(z)
def mluc(t):
    e = t.encode("utf-16-be")
    return pad(b"mluc" + u32(0) + u32(1) + u32(12) + b"enUS" + u32(len(e)) + u32(28) + e)
def text(t): return pad(b"text" + u32(0) + t.encode("ascii") + b"\0")
trc = b"curv" + u32(0) + u32(1) + struct.pack(">H", round(2.2 * 256)) + b"\0\0"
mhc2 = b"MHC2" + u32(0) + u32(2) + s15(0) + s15(nits) + u32(36) + u32(84) + u32(96) + u32(108)
mhc2 += b"".join(s15(v) for v in (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0))
mhc2 += (b"sf32" + s15(0) + s15(1)) * 3
desc = "Wide gamut, gamma 2.2, %d nits" % nits
tags = [(b"cprt", mluc("linux-lab icc.sh")), (b"rTRC", trc), (b"gTRC", trc), (b"bTRC", trc),
        (b"chad", b"sf32" + u32(0) + b"".join(s15(v) for v in (1, 0, 0, 0, 1, 0, 0, 0, 1))),
        (b"rXYZ", xyz(0.906464, 0.421524, 0.025101)), (b"gXYZ", xyz(0.381454, 0.919586, 0.094009)),
        (b"bXYZ", xyz(0.187546, 0.054947, 0.980713)), (b"wtpt", xyz(0.540390, 0.569092, 0.619766)),
        (b"MSCA", text("{\x27Appversion\x27:\x271.0.0.0\x27,\x27D65Adapted\x27:True}")),
        (b"lumi", xyz(nits, nits, nits)), (b"MHC2", mhc2), (b"desc", mluc(desc))]
off, table, blocks, seen = 128 + 4 + 12 * len(tags), b"", b"", {}
for sig, data in tags:
    if id(data) not in seen:
        seen[id(data)] = off; blocks += pad(data); off += len(pad(data))
    table += sig + u32(seen[id(data)]) + u32(len(data))
h = bytearray(128)
now = time.gmtime()
h[4:8], h[8:12], h[12:16], h[16:20], h[20:24] = b"SICC", b"\x04\x40\0\0", b"mntr", b"RGB ", b"XYZ "
struct.pack_into(">6H", h, 24, now.tm_year, now.tm_mon, now.tm_mday, now.tm_hour, now.tm_min, now.tm_sec)
h[36:40], h[40:44] = b"acsp", b"MSFT"
struct.pack_into(">I3i", h, 64, 1, *(int(round(v * 65536)) for v in (0.9642, 1.0, 0.8249)))
h[80:84] = b"MSFT"
p = bytes(h) + u32(len(tags)) + table + blocks
p = struct.pack(">I", len(p)) + p[4:]
open(out, "wb").write(p)
print("%s: %s, %d bytes" % (out, desc, len(p)))
'

output_of() {
    local o
    o=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$1 == "Output:" {print $3}')
    [[ $(wc -l <<<"$o") == 1 && -n $o ]] || die "name the output: $(tr '\n' ' ' <<<"$o")"
    echo "$o"
}

case ${1:-} in
make)
    nits=${2:-2000}
    [[ $nits =~ ^[0-9]+$ ]] || die "NITS is a number"
    file=${3:-$ICC_DIR/wide-gamut-2.2-${nits}nits.icc}
    mkdir -p "$(dirname "$file")"
    python3 -c "$MAKE_PY" "$nits" "$file"
    ;;
use)
    [[ -f ${2:-} ]] || die "icc.sh use FILE [OUTPUT]"
    f=$(readlink -f "$2")
    o=${3:-$(output_of)}
    kscreen-doctor "output.$o.iccprofile.$f" >/dev/null
    kscreen-doctor "output.$o.colorProfileSource.ICC" >/dev/null
    "$0" show
    ;;
show) kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^Output|ICC profile|Color profile source' ;;
*)
    echo "usage: $0 {make [NITS] [FILE] | use FILE [OUTPUT] | show}" >&2
    exit 2
    ;;
esac
