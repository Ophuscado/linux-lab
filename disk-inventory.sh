#!/usr/bin/env bash
# disk-inventory.sh: which disk is where, before the HFS+ to XFS migration.
#
# For every disk behind PCIe over Thunderbolt: the enclosure (its PCI domain, in port
# order), the slot (the SATA port it hangs on, counted from 0), model, size, the HFS+ volume and how full
# it is. Mounts each volume read-only for the count and unmounts it again. Read-only.
#
# Writes two files:
#   ~/disk-inventory.txt   the table for the chat: serial numbers shortened to their last
#                          four characters, nothing else identifying
#   ~/disk-plan.csv        the same rows with the full /dev/disk/by-id names, which is
#                          what the migration works from. Stays on the Mac
#
# The proposed name of each disk is row*8 + slot, rows in enclosure order: the first
# enclosure holds 00 to 07, the second 08 to 15, and so on. Check it against the labels on
# the boxes; the rule "the empty disk of each row is 07, 15, 23, 31" is printed as a test.

set -uo pipefail

OUT=$HOME/disk-inventory.txt
PLAN=$HOME/disk-plan.csv
TMP=/run/disk-inventory

sudo -v || exit 1
sudo modprobe hfsplus 2>/dev/null || true
sudo mkdir -p "$TMP"

rows=()
for dev in /sys/block/sd*; do
    d=${dev##*/}
    path=$(readlink -f "$dev")
    [[ $path == *30000000.pcie/* ]] || continue
    domain=$(grep -oE '/[0-9a-f]{4}:03:00\.0/' <<<"$path" | tr -d / | cut -d: -f1)
    # The slot is the SATA port's place among the controller's ports, so an empty slot
    # does not shift the numbering of those after it.
    host=$(grep -oE '/host[0-9]+/' <<<"$path" | tr -dc 0-9)
    base=$(for h in /sys/class/scsi_host/host*; do
        [[ $(readlink -f "$h") == *"/$domain:03:00.0/"* ]] && echo "${h##*host}"; done | sort -n | head -n 1)
    port=$((host - base))
    byid=$(find /dev/disk/by-id -maxdepth 1 \( -name 'ata-*' -o -name 'wwn-*' \) -lname "*/$d" ! -name '*-part*' | sort | head -n 1)
    serial=$(udevadm info -q property "/dev/$d" 2>/dev/null | sed -n 's/^ID_SERIAL_SHORT=//p')
    model=$(lsblk -dno MODEL "/dev/$d" | tr -s ' ')
    size=$(lsblk -dno SIZE "/dev/$d")
    fstype=""; label=""; used="-"; avail="-"
    for p in $(lsblk -lnpo NAME,TYPE "/dev/$d" | awk '$2 == "part" {print $1}'); do
        t=$(lsblk -no FSTYPE "$p")
        [[ $t == hfsplus || $t == xfs || $t == ext4 ]] || continue
        fstype=$t; label=$(lsblk -no LABEL "$p")
        if findmnt -n "$p" >/dev/null; then
            m=$(findmnt -n -o TARGET "$p" | head -n 1)
        else
            m=$TMP/$d
            sudo mkdir -p "$m"
            sudo mount -o ro "$p" "$m" 2>/dev/null || m=""
        fi
        if [[ -n $m ]]; then
            read -r used avail < <(df -B1 --output=used,avail "$m" | tail -n 1)
            [[ $m == "$TMP/$d" ]] && sudo umount "$m"
        fi
        break
    done
    rows+=("$domain,$port,$d,$byid,$serial,$model,$size,$fstype,$label,$used,$avail")
done

# Enclosures in PCI-domain order become rows 0, 1, 2, 3; SATA ports in order become slots.
{
    echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
    printf '%s\n' "${rows[@]}" | sort -t, -k1,1 -k2,2n | awk -F, -v OFS=, '
        { if ($1 != dom) { dom = $1; row++ }
          print $0, row - 1, $2, sprintf("%02d", (row - 1) * 8 + $2) }'
} >"$PLAN"
chmod 600 "$PLAN"

{
    echo "disks behind PCIe over Thunderbolt: $(( $(wc -l <"$PLAN") - 1 ))"
    printf '%-4s %-3s %-4s %-5s %-4s %-22s %-6s %-7s %-10s %7s %7s\n' name row slot dev serial model size fstype label used avail
    tail -n +2 "$PLAN" | awk -F, '{
        s = $5; if (length(s) > 4) s = "…" substr(s, length(s) - 3)
        u = ($10 == "-") ? "-" : sprintf("%.1fT", $10 / 1e12); a = ($11 == "-") ? "-" : sprintf("%.1fT", $11 / 1e12)
        printf "%-4s %-3s %-4s %-5s %-4s %-22s %-6s %-7s %-10s %7s %7s\n", $14, $12, $13, $3, s, $6, $7, $8, $9, u, a }'
    echo
    echo "test: the empty disk of each row should be its slot 7:"
    tail -n +2 "$PLAN" | awk -F, '$10 != "-" && $10 < 1e9 { printf "  empty: %s (row %s slot %s)\n", $14, $12, $13 }'
    echo
    echo "enclosures seen as USB only (need a replug to get their PCIe tunnel):"
    lsusb 2>/dev/null | grep -i '174c:2463' || echo "  none"
} | tee "$OUT"

echo
echo "Wrote $OUT (attach it) and $PLAN (stays here)."
