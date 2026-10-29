#!/usr/bin/env bash
# tbt-disks.sh: the disk enclosures on this Mac's USB4 ports, reached through PCIe over
# Thunderbolt (the kernel and its patches: kernel/, tbt-kernel.sh).
#
#   tbt-disks.sh status            the rules below, boltd, the Thunderbolt bus, the disks and
#                                  whether each is spinning
#   tbt-disks.sh authorize on|off  a udev rule that authorizes every USB4 device the moment it
#                                  appears, instead of waiting for boltd. boltd files devices by
#                                  a UUID these ASM2464 boxes do not keep unique: with four
#                                  boxes, the second of each UUID pair was never authorized, got
#                                  no PCIe tunnel and fell back to USB after 10 s (KNOWLEDGE.md)
#   tbt-disks.sh readonly on|off   a udev rule that makes every HFS+ volume on those disks
#                                  read-only as it appears (the migration's sources)
#   tbt-disks.sh spindown N|off    the disks stop spinning after N idle minutes (1 to 20, or 30,
#                                  60, ... 330; default 30), now and each time they appear. The
#                                  timer runs in each disk, so a read simply waits for the spin-up
#   tbt-disks.sh mount | umount    their HFS+ volumes read-only under /mnt/tbt/<volume name>
#   tbt-disks.sh bench [MiB]       read-only speed of each disk, N MiB (default 4096) from its
#                                  start, one at a time and then all at once
#   tbt-disks.sh eject             before unplugging an enclosure: refuses while one of its disks
#                                  is mounted, then flushes and detaches the disks. The enclosure's
#                                  own PCI devices stay: taking those away makes the ASM2464
#                                  reconnect by itself 10 s later, with the disks attached again
#
# Until 18 Oct these were stages of tbt-kernel.sh; the rule files kept their names, so rules
# written then are switched off here too.

set -euo pipefail

RO_RULE=/etc/udev/rules.d/99-tbt-readonly.rules
RO_RULE_OLD=/etc/udev/rules.d/00-tbt-readonly.rules
AUTH_RULE=/etc/udev/rules.d/60-tbt-authorize.rules
SPIN_RULE=/etc/udev/rules.d/61-tbt-spindown.rules
MNT=/mnt/tbt

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# Disks behind PCIe over Thunderbolt appear under one of the six tunneled controllers,
# whose device names all end in 30000000.pcie (the internal one is 580000000.pcie). The
# rule runs before any other udev program gets to act on a new disk or partition.
do_authorize() {
    case ${1:-} in
    on)
        printf '%s\n' \
            '# Written by tbt-disks.sh authorize on; removed by authorize off.' \
            '# The kernel authorizes the device itself; boltd then only sees it as authorized.' \
            'ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", ATTR{authorized}="1"' |
            sudo tee "$AUTH_RULE" >/dev/null
        sudo udevadm control --reload
        echo "authorize rule is on: USB4 devices are authorized as they appear. Replug boxes that are in USB mode."
        ;;
    off)
        sudo rm -f "$AUTH_RULE"
        sudo udevadm control --reload
        echo "authorize rule is off; boltd decides again"
        ;;
    *) die "usage: $0 authorize on|off" ;;
    esac
}

do_readonly() {
    case ${1:-} in
    on)
        printf '%s\n' \
            '# Written by tbt-disks.sh readonly on; removed by readonly off.' \
            '# Only HFS+ volumes: a whole disk flagged read-only would also block writes to an XFS' \
            '# partition on it, and the migration needs those. Runs after 60-persistent-storage,' \
            '# which fills in ID_FS_TYPE.' \
            'ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_TYPE}=="hfsplus", DEVPATH=="*30000000.pcie/*", RUN+="/usr/sbin/blockdev --setro /dev/%k"' |
            sudo tee "$RO_RULE" >/dev/null
        sudo rm -f "$RO_RULE_OLD"
        sudo udevadm control --reload
        echo "read-only rule is on: HFS+ volumes behind PCIe over Thunderbolt appear read-only"
        ;;
    off)
        sudo rm -f "$RO_RULE" "$RO_RULE_OLD"
        sudo udevadm control --reload
        echo "read-only rule is off. Disks already present stay read-only until they are"
        echo "replugged, or: sudo blockdev --setrw /dev/sdX"
        ;;
    *) die "usage: $0 readonly on|off" ;;
    esac
}

# Names (sda, sdb, ...) of the disks reached through PCIe over Thunderbolt.
# Asking for the power mode does not wake a disk. smartctl names the idle states of
# newer disks, which hdparm reports as "unknown".
disk_power() {
    local out
    if command -v smartctl >/dev/null; then
        out=$(sudo smartctl -i -n standby "/dev/$1" 2>/dev/null |
            sed -n 's/^Power mode [a-z]*: *//p; s/^Device is in \([A-Z_]*\) mode.*/\1/p' | head -n 1) || true
        [[ -n $out ]] && { echo "$out"; return; }
    fi
    sudo hdparm -C "/dev/$1" 2>&1 | sed -n 's/.*drive state is: *//p' || true
}

# hdparm -S counts in 5 s steps up to 240 (20 minutes) and in 30 minute steps from 241.
do_spindown() {
    local arg=${1:-30} n d hdparm
    hdparm=$(command -v hdparm) || die "hdparm not found (sudo dnf install hdparm)"
    if [[ $arg == off ]]; then
        sudo rm -f "$SPIN_RULE"
        sudo udevadm control --reload
        for d in $(tunnel_disks); do sudo "$hdparm" -q -S 0 "/dev/$d" && echo "$d: timer off"; done
        echo "spin-down rule is off"
        return
    fi
    [[ $arg =~ ^[0-9]+$ ]] || die "usage: $0 spindown MINUTES|off"
    if ((arg >= 1 && arg <= 20)); then
        n=$((arg * 12))
    elif ((arg % 30 == 0 && arg >= 30 && arg <= 330)); then
        n=$((240 + arg / 30))
    else
        die "the disks' timer takes 1 to 20 minutes, or 30, 60, 90 ... 330"
    fi
    printf '%s\n' \
        '# Written by tbt-disks.sh spindown; removed by spindown off.' \
        "ACTION==\"add\", SUBSYSTEM==\"block\", KERNEL==\"sd*[!0-9]\", DEVPATH==\"*30000000.pcie/*\", ATTR{queue/rotational}==\"1\", RUN+=\"$hdparm -q -S $n /dev/%k\"" |
        sudo tee "$SPIN_RULE" >/dev/null
    sudo udevadm control --reload
    for d in $(tunnel_disks); do
        [[ $(cat "/sys/block/$d/queue/rotational") == 1 ]] || continue
        sudo "$hdparm" -q -S "$n" "/dev/$d" && echo "$d: stops after $arg idle minutes"
    done
    echo "spin-down rule is on ($arg minutes). Check later with: $0 status"
}

tunnel_disks() {
    local disk
    for disk in /sys/block/sd*; do
        [[ -e $disk ]] || continue
        [[ $(readlink -f "$disk") == *30000000.pcie/* ]] && echo "${disk##*/}"
    done
    return 0
}

do_mount() {
    local d part fstype label dir n=0
    sudo modprobe hfsplus 2>/dev/null ||
        echo "WARN: no hfsplus module for this kernel"
    for d in $(tunnel_disks); do
        for part in $(lsblk -lnp -o NAME,TYPE "/dev/$d" | awk '$2 == "part" {print $1}'); do
            fstype=$(lsblk -n -o FSTYPE "$part")
            [[ $fstype == hfsplus ]] || continue
            if findmnt -n "$part" >/dev/null; then
                continue
            fi
            label=$(lsblk -n -o LABEL "$part" | tr -c 'A-Za-z0-9._\n-' '_')
            dir=$MNT/${label:-${part##*/}}
            # Two volumes with the same name must not end up on top of each other.
            if mountpoint -q "$dir" 2>/dev/null; then dir=$dir-${part##*/}; fi
            sudo mkdir -p "$dir"
            if sudo mount -t hfsplus -o ro "$part" "$dir"; then n=$((n + 1)); fi
        done
    done
    echo "mounted $n volume(s) read-only"
    findmnt -t hfsplus -o TARGET,SOURCE,SIZE,USED,OPTIONS || true
    echo "Files keep their macOS owner (usually uid 501): read private folders with sudo."
}

do_umount() {
    local src
    for src in $(findmnt -t hfsplus -n -o SOURCE); do
        [[ " $(tunnel_disks | tr '\n' ' ') " == *" $(lsblk -n -o PKNAME "$src") "* ]] || continue
        sudo umount "$src" && echo "unmounted $src"
    done
}

# Reads only. The first read wakes a disk that is spun down, so it is not timed.
do_bench() {
    local mib=${1:-4096} d disks
    disks=$(tunnel_disks)
    [[ -n $disks ]] || die "no disks behind PCIe over Thunderbolt"
    for d in $disks; do sudo dd if="/dev/$d" of=/dev/null bs=1M count=1 iflag=direct status=none; done
    say "one disk at a time, $mib MiB each"
    for d in $disks; do
        printf '%s: ' "$d"
        sudo dd if="/dev/$d" of=/dev/null bs=4M count=$((mib / 4)) iflag=direct 2>&1 | tail -n 1
    done
    say "all disks at once, $mib MiB each"
    for d in $disks; do
        (sudo dd if="/dev/$d" of=/dev/null bs=4M count=$((mib / 4)) iflag=direct 2>&1 |
            tail -n 1 | sed "s/^/$d: /") &
    done
    wait
}

# The disks are flushed and removed from the system while they can still answer; the SATA
# controller and the bridges of the enclosure stay bound, which keeps the enclosure quiet.
do_eject() {
    local d mounted=0 found=0
    for d in $(tunnel_disks); do
        if lsblk -n -o MOUNTPOINTS "/dev/$d" | grep -q .; then
            echo "/dev/$d is mounted:"
            lsblk -o NAME,SIZE,MOUNTPOINTS "/dev/$d"
            mounted=1
        fi
    done
    [[ $mounted == 0 ]] || die "unmount these first ($0 umount), then run eject again"

    sync
    for d in $(tunnel_disks); do
        found=1
        echo "detaching /dev/$d"
        echo 1 | sudo tee "/sys/block/$d/device/delete" >/dev/null
    done
    if [[ $found == 1 ]]; then
        echo "done: the enclosure can be unplugged now"
    else
        echo "no disks are attached through PCIe over Thunderbolt"
    fi
}

do_status() {
    local d a
    echo "authorize rule: $([[ -f $AUTH_RULE ]] && echo on || echo off); boltd: $(systemctl is-active bolt 2>/dev/null || true)"
    echo "read-only rule: $([[ -f $RO_RULE ]] && echo on || echo off)"
    echo "spin-down rule: $([[ -f $SPIN_RULE ]] && sed -n 's/.*hdparm -q -S \([0-9]*\) .*/-S \1/p' "$SPIN_RULE" || echo off)"
    echo "-- thunderbolt bus"
    if [[ -d /sys/bus/thunderbolt/devices ]]; then
        for d in /sys/bus/thunderbolt/devices/*; do
            [[ -e $d ]] || continue
            printf '%s' "${d##*/}"
            for a in vendor_name device_name authorized; do
                [[ -r $d/$a ]] && printf ' %s=%s' "$a" "$(cat "$d/$a" 2>/dev/null)"
            done
            echo
        done
    else
        echo "no thunderbolt bus (this kernel has no Apple USB4 host)"
    fi
    echo "-- disks behind PCIe over Thunderbolt"
    for d in $(tunnel_disks); do printf '%s: %s %s\n' "$d" "$(lsblk -dn -o SIZE,MODEL "/dev/$d" | tr -s ' ')" "$(disk_power "$d")"; done
}

case ${1:-} in
status) do_status ;;
authorize) do_authorize "${2:-}" ;;
readonly) do_readonly "${2:-}" ;;
mount) do_mount ;;
umount) do_umount ;;
bench) do_bench "${2:-}" ;;
spindown) do_spindown "${2:-}" ;;
eject) do_eject ;;
*)
    echo "usage: $0 {status|authorize on|off|readonly on|off|spindown [MINUTES|off]|mount|umount|bench [MiB]|eject}" >&2
    exit 2
    ;;
esac
