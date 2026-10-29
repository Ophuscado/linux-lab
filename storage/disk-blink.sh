#!/usr/bin/env bash
# disk-blink.sh NAME [SECONDS]: make one disk's activity light blink, to find it in the
# box. NAME is the number from disk-inventory.sh (00 to 31) or a device like sdk. Reads
# the disk in small direct reads with pauses; writes nothing.

set -euo pipefail

PLAN=$HOME/disk-plan.csv
name=${1:-}
secs=${2:-30}
[[ -n $name ]] || { echo "usage: $0 NAME [SECONDS]" >&2; exit 2; }

if [[ $name =~ ^[0-9]{2}$ ]]; then
    [[ -r $PLAN ]] || { echo "no $PLAN; run disk-inventory.sh first" >&2; exit 1; }
    dev=$(awk -F, -v n="$name" '$14 == n { print $4 }' "$PLAN")
    [[ -n $dev ]] || { echo "no disk $name in $PLAN" >&2; exit 1; }
else
    dev=/dev/$name
fi
[[ -b $dev ]] || { echo "$dev is not a block device" >&2; exit 1; }

echo "blinking $name ($dev) for $secs s; the others stay quiet"
end=$((SECONDS + secs))
while ((SECONDS < end)); do
    # Far-apart reads keep the head moving, which is what lights the LED on most boxes.
    sudo dd if="$dev" of=/dev/null bs=4k count=1 iflag=direct skip=$((RANDOM * 65536)) status=none
    sleep 0.1
done
echo "done"
