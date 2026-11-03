#!/bin/bash
# hv-pmp.sh: watch macOS start the power management processor (PMP) on this M2 Ultra, under m1n1's hypervisor, so
# Linux can start it the same way. Linux's own attempt hung the machine four times on 3 Nov (KNOWLEDGE, Power
# management): Asahi's driver has no tested M2-family path, and only macOS's own start sequence says what one is.
# m1n1's proxyclient/hv/trace_pmp.py records that sequence (the PMP's messages, its boot arguments, the report words).
#
# The procedure is Asahi's (https://asahilinux.org/docs/sw/m1n1-hypervisor/). Guests: macOS 13.5 or 14.8.3 for M1/M2,
# on a second APFS volume, so no installed macOS is touched. Nothing is built: Fedora's m1n1 (the boot object here,
# /usr/lib/m1n1/m1n1.bin) has the hypervisor, and the host runs m1n1's proxyclient at the same version, so the two
# sides speak the same protocol. Stages, in order, and where each runs:
#
#   stage DIR      Linux: m1n1.bin, its version and this script into DIR/hv-pmp/ (the USB stick)
#   volume         any macOS on the Mac Studio: the APFS containers with their free space and whether Apple still
#                  offers 13.5; prints the two commands that add the volume and fetch the installer (about 30 GB)
#   kernel DIR     macOS 13.5, booted from the new volume: its kernelcache and version into DIR/hv-pmp/
#   recovery       prints the commands for recoveryOS (hold the power button, Options, Terminal): reduced security
#                  and SIP off for the new volume only, m1n1 as its boot object; and the way back
#   host-setup     the second Mac: a venv with the proxyclient's packages (construct, pyserial, asn1) and pyimg4, and
#                  m1n1's source at the version stage recorded, under ~/hv-pmp
#   trace DIR      the second Mac, cabled to the Mac Studio's DFU port (Apple: "the rightmost USB-C port when you're
#                  facing the back") with the Mac Studio booting the new volume: macOS under the hypervisor with trace_pmp.py, the log in
#                  DIR/hv-pmp/trace-<date>.log
#
# Safety: reduced security and SIP apply to the new volume alone (Apple silicon keeps a boot policy per volume); the
# other macOS volumes, the Linux install and the firmware stay as they are. Back: in recoveryOS, Startup Security
# Utility, Full Security for the new volume (that drops the custom boot object), or delete the volume.
set -uo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
args='debug=0x14e serial=3 apcie=0xfffffffe -enable-kprintf-spam wdt=-1 clpc=0'

case ${1:-} in
stage)
    d=${2:?usage: $0 stage DIR}/hv-pmp; mkdir -p "$d" || die "cannot write $d"
    cp /usr/lib/m1n1/m1n1.bin "$d/" || die "no /usr/lib/m1n1/m1n1.bin"
    v=$(rpm -q --qf '%{VERSION}' m1n1 2>/dev/null) || v=$(strings /usr/lib/m1n1/m1n1.bin | grep -m1 -E '^v[0-9]+\.[0-9]+\.[0-9]+')
    echo "${v#v}" >"$d/m1n1-version.txt"; cp "$0" "$d/hv-pmp.sh"; chmod +x "$d/hv-pmp.sh"
    sync; echo "staged m1n1 ${v#v} and hv-pmp.sh in $d"
    ;;
volume)
    [[ $(uname) == Darwin ]] || die "run this in macOS"
    diskutil apfs list | grep -E 'Container disk|Size \(Capacity Ceiling\)|Capacity Not Allocated|Name:|Role'
    echo "--- full installers Apple offers for 13.5 and 14.8.3:"
    softwareupdate --list-full-installers 2>/dev/null | grep -E 'Version: (13\.5|14\.8\.3),' || echo "neither is offered: archive.org keeps their InstallAssistant.pkg (Asahi's guide)"
    cat <<'EOF'
--- then, with CONTAINER the disk of the container that holds macOS (at least ~40 GB not allocated):
diskutil apfs addVolume CONTAINER APFS macOSTest -mountpoint /Volumes/macOSTest
softwareupdate --fetch-full-installer --full-installer-version 13.5
# install it from Applications onto macOSTest (not over an installed macOS), then: hv-pmp.sh kernel /Volumes/UNTITLED
EOF
    ;;
kernel)
    [[ $(uname) == Darwin ]] || die "run this in macOS 13.5, booted from the new volume"
    d=${2:?usage: $0 kernel DIR}/hv-pmp; mkdir -p "$d" || die "cannot write $d"
    g=$(diskutil info -plist / | plutil -extract APFSVolumeGroupID raw -o - - 2>/dev/null) || die "no volume group for /"
    k=$(ls /System/Volumes/Preboot/"$g"/boot/*/System/Library/Caches/com.apple.kernelcaches/kernelcache 2>/dev/null | head -n 1)
    [[ -f $k ]] || die "no kernelcache under /System/Volumes/Preboot/$g"
    cp "$k" "$d/kernelcache" && sw_vers >"$d/guest-version.txt" && sync
    echo "copied $(sw_vers -productVersion)'s kernelcache to $d"
    ;;
recovery)
    cat <<'EOF'
In recoveryOS (power button held until Options; Options, Continue; Utilities, Terminal), with macOSTest set as the
startup disk first (Apple menu, Startup Disk, in that macOS or here):
  bputil -nkcas                 # reduced security for the volume it asks about: choose macOSTest's UUID
  csrutil disable               # bputil turns SIP back on; off again, for macOSTest
  nvram boot-args=-v
  kmutil configure-boot -c /Volumes/UNTITLED/hv-pmp/m1n1.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/macOSTest
Then shut down, cable the second Mac to the DFU port, power on: m1n1 starts on macOSTest and waits for the host.
Back: Startup Security Utility in recoveryOS, Full Security for macOSTest; or delete macOSTest in Disk Utility.
EOF
    ;;
host-setup)
    [[ $(uname) == Darwin ]] || echo "WARN: written for a macOS host; Linux works too with python3-venv"
    h=$HOME/hv-pmp; mkdir -p "$h"
    v=$(cat "$here/m1n1-version.txt" 2>/dev/null) || die "no m1n1-version.txt beside this script: stage it from Linux"
    python3 -m venv "$h/venv" || die "python3 -m venv failed (Command Line Tools: xcode-select --install)"
    "$h/venv/bin/pip" install -q construct==2.10.70 pyserial==3.5 asn1==3.3.0 pyimg4 || die "pip install failed"
    [[ -d $h/m1n1 ]] || git clone -q --depth 1 -b "v$v" https://github.com/AsahiLinux/m1n1 "$h/m1n1" || die "git clone of m1n1 v$v failed"
    echo "ready: $h (m1n1 v$v, $("$h/venv/bin/python" --version))"
    ;;
trace)
    d=${2:?usage: $0 trace DIR}/hv-pmp; h=$HOME/hv-pmp; py=$h/venv/bin/python
    [[ -x $py && -d $h/m1n1 ]] || die "run $0 host-setup first"
    [[ -f $d/kernelcache ]] || die "no $d/kernelcache: run '$0 kernel' in macOS 13.5 first"
    [[ -f $h/kernelcache.macho ]] || "$h/venv/bin/pyimg4" im4p extract -i "$d/kernelcache" -o "$h/kernelcache.macho" ||
        die "pyimg4 could not unpack the kernelcache (img4tool -ep / -eo does the same: Asahi's guide)"
    # m1n1's proxyclient opens /dev/cu.usbmodemP_01 on macOS unless M1N1DEVICE names another
    dev=${M1N1DEVICE:-/dev/cu.usbmodemP_01}
    [[ -e $dev ]] || die "no $dev: is the cable in the DFU port and m1n1 up on macOSTest? present: $(ls /dev/cu.usbmodem* 2>/dev/null | tr '\n' ' ')"
    log=$d/trace-$(date +%Y%m%d-%H%M%S).log
    echo "tracing into $log; quit with Ctrl-C once macOS is at its login window"
    cd "$h/m1n1" && "$py" proxyclient/tools/run_guest.py -m proxyclient/hv/trace_pmp.py -l "$log" "$h/kernelcache.macho" -- "$args"
    sync; echo "log: $log ($(wc -l <"$log") lines)"
    ;;
*)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 2
    ;;
esac
