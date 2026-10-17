#!/usr/bin/env bash
# disk-check.sh: a quick, read-only health check of one disk, for a USB disk that hangs.
#
#   sudo ./disk-check.sh WD50NMZW        the disk whose model or serial contains this text, or
#   sudo ./disk-check.sh /dev/sdb        that device
#
# Prints: the disk and its volumes; the USB link it sits on (speed, driver uas or usb-storage);
# SMART health, the attributes that count damage (reallocated, pending, uncorrectable sectors,
# CRC errors on the cable) and the error log, through the USB bridge (-d sat); the kernel's lines
# about it since boot (resets, timeouts, I/O errors); three reads of 8 MiB, at the start, the
# middle and near the end, with their speed. Then it starts the drive's own short self-test
# (about 2 minutes, inside the drive; read-only); 'smartctl -l selftest -d sat DEV' shows the
# result afterwards. Writes nothing to the disk.
#
# A read that hangs is the finding: the 8 MiB reads give up after 60 s each, but a disk stuck in
# the kernel (state D) cannot be interrupted; then unplug it.

set -uo pipefail
[[ $EUID == 0 ]] || { echo "run as root: sudo $0 $*" >&2; exit 1; }
[[ $# == 1 ]] || { echo "usage: $0 MODEL-OR-SERIAL-TEXT | /dev/sdX" >&2; exit 2; }
command -v smartctl >/dev/null || { echo "smartctl missing: dnf install smartmontools" >&2; exit 1; }

if [[ $1 == /dev/* ]]; then
    d=$1
else
    d=$(lsblk -dnpo NAME,MODEL,SERIAL | grep -i -- "$1" | awk '{ print $1; exit }')
fi
[[ -n ${d:-} && -b $d ]] || { echo "no disk matches $1"; lsblk -dno NAME,TRAN,MODEL,SIZE; exit 1; }
k=${d##*/}

echo "== $d"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$d"
echo "== link"
p=$(readlink -f "/sys/block/$k")
intf=$(grep -oE '/[0-9]+-[0-9.]+:[0-9]+\.[0-9]+/' <<<"$p" | tail -n 1 | tr -d /)
if [[ -n $intf ]]; then
    usb=${intf%%:*}
    echo "usb $usb: $(cat "/sys/bus/usb/devices/$usb/speed" 2>/dev/null) Mb/s, driver $(basename "$(readlink -f "/sys/bus/usb/devices/$intf/driver")")"
else
    usb=none
    echo "not on USB: $p"
fi
echo "== SMART (through the USB bridge)"
smartctl -i -H -A -l error -d sat "$d" 2>&1 | grep -vE '^(smartctl|Copyright|$)' |
    grep -E 'Model|Serial|Capacity|Rotation|SMART overall|result|^ID#|Reallocated|Pending|Offline_Uncorrectable|Reported_Uncorrect|UDMA_CRC|Power_On_Hours|Temperature|Load_Cycle|Error [0-9]+ occurred|No Errors|ATA Error Count' || true
echo "== kernel lines since boot"
journalctl -k -b --no-pager -o short-iso 2>/dev/null | grep -E "\b${k}\b|\[${k}\]|usb ${usb}[:.]|uas_eh|reset (high|Super)Speed" | tail -n 20 | cut -c12-200
echo "== reads (8 MiB each)"
mib=$(($(blockdev --getsize64 "$d") / 1048576))
for at in 0 $((mib / 2)) $((mib - 16)); do
    t0=$(date +%s.%N)
    if timeout -k 5 60 dd if="$d" of=/dev/null bs=1M count=8 skip="$at" iflag=direct status=none; then
        awk -v at="$at" -v t0="$t0" -v t1="$(date +%s.%N)" 'BEGIN { printf "  at %8d MiB: %6.1f MB/s\n", at, 8.389 / (t1 - t0) }'
    else
        echo "  at $at MiB: FAILED or over 60 s"
    fi
done
echo "== short self-test"
smartctl -t short -d sat "$d" 2>&1 | grep -E 'Testing has begun|Please wait|aborted|not supported|failed' || true
echo "afterwards: smartctl -l selftest -d sat $d"
