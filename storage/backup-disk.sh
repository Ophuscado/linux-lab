#!/usr/bin/env bash
# backup-disk.sh: keep the USB backup disk powered off between backups, and power it on for one.
# A disk powered off by udisks (or one that dropped off the bus after hours asleep) only comes back
# when its USB port is cycled; that needs root, so 'setup' installs a small root unit that cycles
# the one recorded port, and a polkit rule that lets you start that unit and nothing else.
#
#   sudo ./backup-disk.sh setup [LABEL]  once, with the disk plugged in: records its USB port and
#                                        serial in /etc/backup-disk.conf, installs the unit
#                                        backup-disk-wake.service and its polkit rule
#   sudo ./backup-disk.sh setup --usb B-P --serial S [LABEL]
#                                        the same for a disk that is gone now (dropped off the
#                                        bus): its USB address and serial from the kernel log
#   ./backup-disk.sh on [LABEL]          power it on (cycles the port if the disk is gone) and mount it
#   ./backup-disk.sh off [LABEL]         unmount it and power it off (udisksctl power-off)
#   ./backup-disk.sh status [LABEL]      what is recorded and whether the disk is there
#   sudo ./backup-disk.sh uninstall      removes the unit, the rule, the helper and the record
#   backup-disk.sh wake                  the unit's step (root): cycle the recorded port when its
#                                        disk is gone and nothing else sits on that port
# backup-home.sh calls 'on' before a backup and 'off' after it once setup has been run.
# Default LABEL "BACKUP (ext4)". Test hooks: BD_SYS (sysfs, /sys), BD_ETC (/etc), BD_LIBEXEC
# (/usr/local/libexec), BD_UNITS (/etc/systemd/system), BD_WAIT (seconds to wait, 60: a disk spins up).
set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
SYS=${BD_SYS:-/sys}
ETC=${BD_ETC:-/etc}
LIBEXEC=${BD_LIBEXEC:-/usr/local/libexec}
UNITS=${BD_UNITS:-/etc/systemd/system}
WAIT=${BD_WAIT:-60}
CONF=$ETC/backup-disk.conf
UNIT=backup-disk-wake.service
cmd=${1:-status}; [[ $# -gt 0 ]] && shift
want_usb="" want_serial=""
while [[ ${1:-} == --usb || ${1:-} == --serial ]]; do
    [[ $# -ge 2 ]] || die "$1 needs a value"
    [[ $1 == --usb ]] && want_usb=$2 || want_serial=$2; shift 2
done
label=${1:-BACKUP (ext4)}

# The USB device (sysfs path) of a block device: the nearest parent with a serial and a busnum.
usb_of_block() {
    local d
    d=$(readlink -f "$SYS/class/block/$1/device") || return 1
    while [[ $d == "$SYS"/* && $d != "$SYS" ]]; do
        [[ -f $d/serial && -f $d/busnum ]] && { echo "$d"; return 0; }
        d=${d%/*}
    done
    return 1
}
# The present USB device with this serial, if any.
usb_by_serial() {
    local s
    for s in "$SYS"/bus/usb/devices/*/serial; do
        [[ -f $s && $(<"$s") == "$1" ]] && { readlink -f "${s%/serial}"; return 0; }
    done
    return 1
}
# The hub port a USB device hangs on: <parent interface>/<hub>-port<N>, as sysfs names it.
port_of_usb() {
    local dev=$1 name parent hub portnum
    name=${dev##*/}                       # e.g. 2-1, or 2-1.3 behind a hub
    portnum=${name##*[-.]}
    parent=${dev%/*}                      # the hub (usb2 or 2-1)
    hub=${parent##*/}
    local intf=$hub:1.0
    [[ $hub == usb* ]] && intf=${hub#usb}-0:1.0   # a root hub's interface is N-0:1.0
    [[ -e $parent/$intf/$hub-port$portnum/disable ]] && { echo "$parent/$intf/$hub-port$portnum"; return 0; }
    return 1
}
conf() { [[ -f $CONF ]] || return 1; # shellcheck disable=SC1090
    . "$CONF"; }
# The partition with this label. Not /dev/disk/by-label: udev escapes more than spaces there
# ("BACKUP (ext4)" is BACKUP\x20\x28ext4\x29), which is why 'on' once waited for a disk already back.
dev_of_label() {
    local line re='^PATH="([^"]*)" LABEL="(.*)"$'
    while IFS= read -r line; do
        [[ $line =~ $re && ${BASH_REMATCH[2]} == "$label" ]] && { echo "${BASH_REMATCH[1]}"; return 0; }
    done < <(lsblk -nPo PATH,LABEL 2>/dev/null)
    return 0
}
mounted_at() { findmnt -n -o TARGET -S "LABEL=$label" 2>/dev/null | head -n 1 || true; }

case $cmd in
setup)
    ((EUID == 0)) || die "setup needs root: sudo $0 setup"
    user=${SUDO_USER:-}; [[ -n $user && $user != root ]] || die "run it with sudo from your own account, so the rule names you"
    if [[ -n $want_usb ]]; then
        [[ $want_usb =~ ^[0-9]+-[0-9]+(\.[0-9]+)*$ && -n $want_serial ]] || die "--usb takes an address such as 2-1, and --serial is needed with it"
        bus=${want_usb%%-*} parent=${want_usb%.*}; [[ $parent == "$want_usb" ]] && parent=usb$bus
        usb=$(readlink -f "$SYS/bus/usb/devices/$parent")/$want_usb   # the device itself may be gone
        [[ -d ${usb%/*} ]] || die "no USB hub $parent here"
        serial=$want_serial
    else
        dev=$(dev_of_label); [[ -b $dev ]] || die "no disk labeled '$label' is plugged in; if it dropped off the bus, give its address and serial from the kernel log: $0 setup --usb B-P --serial S"
        blk=$(lsblk -no PKNAME "$dev" | head -n 1); blk=${blk:-${dev##*/}}
        usb=$(usb_of_block "$blk") || die "$dev is not on USB"
        serial=$(<"$usb/serial")
    fi
    port=$(port_of_usb "$usb") || die "no port with a disable switch for $usb (kernel too old?)"
    printf '# Written by backup-disk.sh setup; removed by uninstall.\nBD_LABEL=%q\nBD_SERIAL=%q\nBD_PORT=%q\n' "$label" "$serial" "$port" >"$CONF"
    install -D -m 755 "$(readlink -f "$0")" "$LIBEXEC/backup-disk-wake"
    cat >"$UNITS/$UNIT" <<EOF
# Written by backup-disk.sh setup: powers the backup disk's USB port back on (cycles it) when the disk is gone.
[Unit]
Description=Power on the USB backup disk
[Service]
Type=oneshot
Environment=BD_ETC=$ETC
ExecStart=$LIBEXEC/backup-disk-wake wake
EOF
    install -d -m 755 "$ETC/polkit-1/rules.d"
    cat >"$ETC/polkit-1/rules.d/50-backup-disk-wake.rules" <<EOF
// Written by backup-disk.sh setup: $user may start $UNIT, nothing else.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" && action.lookup("unit") == "$UNIT" &&
        action.lookup("verb") == "start" && subject.user == "$user") {
        return polkit.Result.YES;
    }
});
EOF
    [[ -z ${BD_SYS:-} ]] && systemctl daemon-reload
    echo "recorded: '$label', serial $serial, port $port; $user may start $UNIT"
    ;;
wake)
    conf || die "no $CONF: run setup first"
    usb_by_serial "$BD_SERIAL" >/dev/null && { echo "the disk is there"; exit 0; }
    [[ -e $BD_PORT/disable ]] || die "the recorded port $BD_PORT is gone (another hub or port now?): run setup again with the disk plugged in"
    [[ -e $BD_PORT/device ]] && die "another device sits on $BD_PORT; not cycling it"
    echo 1 >"$BD_PORT/disable"; sleep 1; echo 0 >"$BD_PORT/disable"
    for ((i = 0; i < WAIT; i++)); do usb_by_serial "$BD_SERIAL" >/dev/null && { echo "the disk is back after cycling $BD_PORT"; exit 0; }; sleep 1; done
    die "cycled $BD_PORT, the disk did not come back in $WAIT s: replug it"
    ;;
on)
    conf || die "no $CONF: run 'sudo $0 setup' first"
    [[ -n $(mounted_at) ]] && { mounted_at; exit 0; }
    if [[ ! -b $(dev_of_label) ]]; then
        systemctl start "$UNIT" || die "could not start $UNIT"
        for ((i = 0; i < WAIT; i++)); do [[ -b $(dev_of_label) ]] && break; sleep 1; done
        [[ -b $(dev_of_label) ]] || die "the disk is powered but '$label' did not show up"
    fi
    udisksctl mount -b "$(dev_of_label)" >/dev/null || die "could not mount '$label'"
    mounted_at
    ;;
off)
    dev=$(dev_of_label); [[ -b $dev ]] || { echo "the disk is off already"; exit 0; }
    blk=$(lsblk -no PKNAME "$dev" | head -n 1)
    # Every mounted partition of the drive (the disk also has an exFAT one macOS reads), not only the label's.
    while read -r p mp; do
        [[ -n $mp ]] || continue
        sync -f "$mp"; udisksctl unmount -b "$p" >/dev/null || die "could not unmount $p at $mp (in use?)"
    done < <(lsblk -rno PATH,MOUNTPOINT "/dev/${blk:-${dev##*/}}" | tail -n +2)
    udisksctl power-off -b "/dev/${blk:-${dev##*/}}" || die "could not power off '$label'"
    echo "'$label' is off"
    ;;
status)
    if conf; then echo "recorded: '$BD_LABEL', serial $BD_SERIAL, port $BD_PORT"; else echo "not set up (sudo $0 setup)"; fi
    m=$(mounted_at); if [[ -n $m ]]; then echo "on, mounted at $m"; elif [[ -b $(dev_of_label) ]]; then echo "on, not mounted"; else echo "off or gone"; fi
    ;;
uninstall)
    ((EUID == 0)) || die "uninstall needs root"
    rm -f "$CONF" "$UNITS/$UNIT" "$ETC/polkit-1/rules.d/50-backup-disk-wake.rules" "$LIBEXEC/backup-disk-wake"
    [[ -z ${BD_SYS:-} ]] && systemctl daemon-reload
    echo "removed"
    ;;
*) die "usage: $0 setup|on|off|status|uninstall [LABEL]" ;;
esac
