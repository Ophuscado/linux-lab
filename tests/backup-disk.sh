#!/bin/bash
# backup-disk.sh's port logic on a fake sysfs (no root, no hardware): finding the port of a USB disk,
# 'wake' cycling only an empty recorded port, refusing when another device sits there, and
# leaving the port alone when the disk is present.
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/var/tmp}/backup-disk.XXXX"); S=$T/sys; fail=0
hub=$S/devices/platform/xhci/usb2
mkdir -p "$hub/2-0:1.0/usb2-port1" "$hub/2-0:1.0/usb2-port2" "$S/bus/usb/devices" "$T/etc"
echo 0 >"$hub/2-0:1.0/usb2-port1/disable"; echo 0 >"$hub/2-0:1.0/usb2-port2/disable"
disk=$hub/2-1; mkdir -p "$disk/2-1:1.0/host0/target0:0:0/0:0:0:0"
echo SER123 >"$disk/serial"; echo 2 >"$disk/busnum"
ln -s "$disk" "$S/bus/usb/devices/2-1"
mkdir -p "$S/class/block/sdz"; ln -s "$disk/2-1:1.0/host0/target0:0:0/0:0:0:0" "$S/class/block/sdz/device"
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
# shellcheck disable=SC1090,SC2034
fns=$(sed -n '/^usb_of_block()/,/^conf()/p' "$REPO/storage/backup-disk.sh" | sed '$d'); SYS=$S; eval "$fns"
usb=$(usb_of_block sdz); ok "disk's USB device" '[[ $usb == "$disk" ]]'
port=$(port_of_usb "$usb"); ok "its port" '[[ $port == "$hub/2-0:1.0/usb2-port1" ]]'
printf 'BD_LABEL=x\nBD_SERIAL=SER123\nBD_PORT=%q\n' "$port" >"$T/etc/backup-disk.conf"
run() { BD_SYS=$S BD_ETC=$T/etc BD_WAIT=1 bash "$REPO/storage/backup-disk.sh" wake 2>&1; }
out=$(run); ok "present: not cycled" '[[ $out == "the disk is there" ]]'
rm "$S/bus/usb/devices/2-1"                                   # the disk drops off the bus
mkdir -p "$hub/2-9"; ln -s "$hub/2-9" "$port/device"                             # something else on the port
out=$(run); ok "other device: refused" '[[ $out == *"another device"* && $(<"$port/disable") == 0 ]]'
rm "$port/device"
out=$(run); ok "gone: cycled, reports it did not come back" '[[ $out == *"did not come back"* && $(<"$port/disable") == 0 ]]'
# the label lookup, with a label udev would escape: a fake lsblk
mkdir -p "$T/bin"; printf '#!/bin/sh\necho %s\necho %s\n' "'PATH=\"/dev/sda1\" LABEL=\"BACKUP\"'" "'PATH=\"/dev/sdz1\" LABEL=\"BACKUP (ext4)\"'" >"$T/bin/lsblk"; chmod +x "$T/bin/lsblk"
fns=$(sed -n '/^dev_of_label()/,/^}/p' "$REPO/storage/backup-disk.sh"); eval "$fns"
got=$(PATH=$T/bin:$PATH; label='BACKUP (ext4)'; dev_of_label); ok "label with spaces and brackets" '[[ $got == /dev/sdz1 ]]'
got=$(PATH=$T/bin:$PATH; label='NONE'; dev_of_label); ok "absent label: empty" '[[ -z $got ]]'
# setup for a disk that is gone: the port from its USB address (needs root for the EUID check)
if ((EUID == 0)); then
    rm -rf "$disk"; mkdir -p "$T/lib" "$T/units"; ln -s "$hub" "$S/bus/usb/devices/usb2"
    out=$(SUDO_USER=tester BD_SYS=$S BD_ETC=$T/etc BD_LIBEXEC=$T/lib BD_UNITS=$T/units bash "$REPO/storage/backup-disk.sh" setup --usb 2-1 --serial SER123 2>&1)
    ok "setup --usb: port recorded" 'grep -q "usb2-port1" "$T/etc/backup-disk.conf" && grep -q "subject.user == \"tester\"" "$T/etc/polkit-1/rules.d/50-backup-disk-wake.rules" && [[ -x $T/lib/backup-disk-wake && -f $T/units/backup-disk-wake.service ]]'
fi
rm -rf "$T"; exit $fail
