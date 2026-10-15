#!/usr/bin/env bash
# settings.sh: the standing settings of this machine, as one switch, each one a file this
# script owns and removes again.
#
#   settings.sh install [SPINDOWN_MIN]   everything below (default spin-down 30 min)
#   settings.sh uninstall                remove all of it
#   settings.sh status                   what is in force
#   settings.sh sleep-hook on|off|test   the suspend hook alone (see below)
#
# What "install" puts in place, and where it comes from:
#   authorize rule   tbt-kernel.sh authorize on   USB4 devices are authorized as they appear
#                                                 (boltd mixes up the boxes' shared UUIDs)
#   spin-down rule   tbt-kernel.sh spindown N     enclosure disks stand by after N minutes
#   mouse and paste  ux-fix.sh on                 no middle-click emulation, slower scroll,
#                                                 no primary-selection paste (KWin)
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

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

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
    if [[ -f /etc/snapraid.conf ]]; then "$HERE/snapraid-setup.sh" timers on; else echo "SnapRAID timers: later, once /etc/snapraid.conf exists (snapraid-setup.sh install)"; fi
    echo "suspend hook: not installed (untested); settings.sh sleep-hook on when you can test a suspend"
    ;;
uninstall)
    "$HERE/tbt-kernel.sh" authorize off
    "$HERE/tbt-kernel.sh" spindown off
    "$HERE/ux-fix.sh" off
    [[ -f /etc/snapraid.conf ]] && "$HERE/snapraid-setup.sh" timers off
    sudo rm -f "$HOOK"
    echo "removed"
    ;;
status)
    "$HERE/tbt-kernel.sh" status 2>/dev/null | grep -iE 'authorize|spin' || true
    "$HERE/ux-fix.sh" show
    [[ -f /etc/snapraid.conf ]] && "$HERE/snapraid-setup.sh" timers status
    echo "suspend hook: $([[ -x $HOOK ]] && echo "on ($HOOK)" || echo off)"
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
    echo "usage: $0 {install [SPINDOWN_MIN] | uninstall | status | sleep-hook on|off|test}" >&2
    exit 2
    ;;
esac
