#!/usr/bin/env bash
# settings.sh: the standing settings of this machine, as one switch, each one a file this
# script owns and removes again.
#
#   settings.sh install [SPINDOWN_MIN]   everything below (default spin-down 30 min)
#   settings.sh uninstall                remove all of it
#   settings.sh status                   what is in force
#   settings.sh sleep-hook on|off|test   the suspend hook alone (see below)
#   settings.sh usb-cap on|off           the USB dirty cap alone (see below)
#
# What "install" puts in place, and where it comes from:
#   authorize rule   tbt-kernel.sh authorize on   USB4 devices are authorized as they appear
#                                                 (boltd mixes up the boxes' shared UUIDs)
#   spin-down rule   tbt-kernel.sh spindown N     enclosure disks stand by after N minutes
#   mouse and paste  ux-fix.sh on                 no middle-click emulation, slower scroll,
#                                                 no primary-selection paste (KWin)
#   USB dirty cap    this script                  a USB disk holds at most 256 MiB of unwritten
#                                                 data, so a long copy onto a slow one no longer
#                                                 stalls every writer, sync and shutdown
#   SnapRAID timers  snapraid-setup.sh timers on  only once /etc/snapraid.conf exists
#   suspend hook     this script                  before sleep: unmount the pool and the
#                                                 enclosure disks and detach the tunneled PCIe
#                                                 devices; after resume: rescan and mount -a.
#                                                 UNTESTED on this machine: "install" leaves
#                                                 it off; "sleep-hook on" turns it on once
#                                                 you can try a suspend with the boxes on.
# The read-only rule of the migration (tbt-kernel.sh readonly) is not a standing setting
# and is not touched here.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK=${SETTINGS_HOOK:-/usr/lib/systemd/system-sleep/tbt-enclosures}
POOL=${SR_POOL:-/srv/pool}
ROOT=${SR_ROOT:-/mnt}

USB_RULE=${SETTINGS_USB_RULE:-/etc/udev/rules.d/62-usb-dirty-cap.rules}
USB_CAP=${SETTINGS_USB_CAP:-268435456}

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# The dirty cap of USB disks. A slow USB disk (the backup disk is a 5400 rpm 2.5" drive on
# usb-storage, one command at a time) could collect gigabytes of unwritten data in the page cache
# during a long copy: every writer on the machine was then throttled with it, and sync and shutdown
# waited hours for it. With strict_limit and max_bytes on its writeback device, at most USB_CAP
# bytes wait for it: the copy onto it slows to the disk's own speed, nothing else does.
usb_cap_now() { # on|off|status: every USB disk present now
    local d b n=0
    for d in /sys/block/sd*; do
        [[ -e $d && $(readlink -f "$d") == */usb[0-9]*/* ]] || continue
        b=/sys/class/bdi/$(cat "$d/dev")
        [[ -e $b/max_bytes && -e $b/strict_limit ]] || { echo "${d##*/}: this kernel has no per-disk cap"; continue; }
        if [[ $1 == on ]]; then
            echo "$USB_CAP" | sudo tee "$b/max_bytes" >/dev/null
            echo 1 | sudo tee "$b/strict_limit" >/dev/null
        elif [[ $1 == off ]]; then
            echo 100 | sudo tee "$b/max_ratio" >/dev/null
            echo 0 | sudo tee "$b/strict_limit" >/dev/null
        fi
        echo "${d##*/}: $(($(cat "$b/max_bytes") / 1048576)) MiB unwritten at most, strict $(cat "$b/strict_limit")"; n=$((n + 1))
    done
    ((n > 0)) || echo "no USB disk attached now"
}
usb_cap() {
    case $1 in
    on)
        printf '%s\n' \
            '# Written by settings.sh usb-cap on; removed by usb-cap off and by uninstall.' \
            '# A USB disk may hold at most this much unwritten data in the page cache (strict per-disk limit).' \
            "ACTION==\"add\", SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"disk\", ENV{ID_BUS}==\"usb\", RUN+=\"/bin/sh -c 'echo $USB_CAP > /sys/class/bdi/%M:%m/max_bytes; echo 1 > /sys/class/bdi/%M:%m/strict_limit'\"" |
            sudo tee "$USB_RULE" >/dev/null
        sudo udevadm control --reload
        usb_cap_now on
        ;;
    off)
        sudo rm -f "$USB_RULE"
        sudo udevadm control --reload
        usb_cap_now off
        ;;
    esac
}

write_hook() {
    sudo mkdir -p "$(dirname "$HOOK")"
    sudo tee "$HOOK" >/dev/null <<EOF
#!/bin/bash
# Written by settings.sh sleep-hook on; removed by sleep-hook off and by uninstall.
# systemd-sleep hook: the PCIe tunnels of the enclosures do not survive a suspend, so the
# disks behind them are unmounted and their PCIe devices detached before sleep, and the
# buses rescanned and fstab mounted again after resume (the thunderbolt driver rebuilds
# the tunnels by itself). Set DRY=1 to print instead of act.
POOL=$POOL
ROOT=$ROOT
run() { if [[ -n \${DRY:-} ]]; then echo "would: \$*"; else "\$@"; fi; }
tunneled() { # PCI devices behind a tunneled controller (its name ends in 30000000.pcie), endpoints only
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ \$(readlink -f "\$d") == *30000000.pcie/* ]] || continue
        [[ \${d##*/} == *:00:00.0 ]] && continue   # the root port stays
        echo "\$d"
    done
}
case \$1 in
pre)
    findmnt -n "\$POOL" >/dev/null && run umount "\$POOL"
    for m in \$(findmnt -rn -o TARGET | grep -E "^\$ROOT/(hd|parity)/" | sort -r); do run umount "\$m"; done
    for d in \$(tunneled); do run sh -c "echo 1 > \$d/remove"; done
    ;;
post)
    run sh -c 'echo 1 > /sys/bus/pci/rescan'
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        udevadm settle 2>/dev/null || true
        [[ \$(ls /dev/disk/by-label/ 2>/dev/null | grep -c '^HD_') -ge 32 ]] && break
        sleep 3
    done
    run mount -a
    ;;
esac
exit 0
EOF
    sudo chmod 755 "$HOOK"
}

case ${1:-} in
install)
    spin=${2:-30}
    "$HERE/tbt-kernel.sh" authorize on
    "$HERE/tbt-kernel.sh" spindown "$spin"
    "$HERE/ux-fix.sh" on
    usb_cap on
    if [[ -f /etc/snapraid.conf ]]; then "$HERE/snapraid-setup.sh" timers on; else echo "SnapRAID timers: later, once /etc/snapraid.conf exists (snapraid-setup.sh install)"; fi
    echo "suspend hook: not installed (untested); settings.sh sleep-hook on when you can test a suspend"
    ;;
uninstall)
    "$HERE/tbt-kernel.sh" authorize off
    "$HERE/tbt-kernel.sh" spindown off
    "$HERE/ux-fix.sh" off
    usb_cap off
    [[ -f /etc/snapraid.conf ]] && "$HERE/snapraid-setup.sh" timers off
    sudo rm -f "$HOOK"
    echo "removed"
    ;;
status)
    "$HERE/tbt-kernel.sh" status 2>/dev/null | grep -iE 'authorize|spin' || true
    "$HERE/ux-fix.sh" show
    [[ -f /etc/snapraid.conf ]] && "$HERE/snapraid-setup.sh" timers status
    echo "suspend hook: $([[ -x $HOOK ]] && echo "on ($HOOK)" || echo off)"
    echo "USB dirty cap: $([[ -f $USB_RULE ]] && echo "on ($USB_RULE)" || echo off)"; usb_cap_now status 2>/dev/null | sed 's/^/    /' || true
    ;;
usb-cap)
    case ${2:-} in on | off) usb_cap "$2" ;; *) die "usage: $0 usb-cap on|off" ;; esac
    ;;
sleep-hook)
    case ${2:-} in
    on) write_hook; echo "suspend hook on: $HOOK. Test: systemctl suspend with the boxes on, then findmnt $POOL" ;;
    off) sudo rm -f "$HOOK"; echo "suspend hook off" ;;
    test) write_hook; echo "--- pre (dry)"; DRY=1 "$HOOK" pre; echo "--- post (dry)"; DRY=1 "$HOOK" post ;;
    *) die "usage: $0 sleep-hook on|off|test" ;;
    esac
    ;;
*)
    echo "usage: $0 {install [SPINDOWN_MIN] | uninstall | status | sleep-hook on|off|test | usb-cap on|off}" >&2
    exit 2
    ;;
esac
