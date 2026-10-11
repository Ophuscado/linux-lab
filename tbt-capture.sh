#!/usr/bin/env bash
# tbt-capture.sh: record USB4 enclosure plug-ins on the trial kernel, with driver
# debug output switched on, into a single text file to send back.
#
# It only reads state and toggles kernel debug printing (switched off again at the end).
# Run it while booted into the 7.2.2-tbtwip kernel.
#
# The router firmware can log about 30 identical link-error lines per second; they are
# counted, not listed. The second round detaches the disks first (tbt-kernel.sh eject)
# and then replugs: it exercises the path that takes the PCIe
# controller down and brings it up again, without pulling disks away from their driver.
#
# The machine froze during a replug once and took the capture with it. The kernel log is
# therefore also copied, line by line and flushed to disk, into a second file (.klog),
# and the capture itself is flushed after every step.

set -uo pipefail # deliberately not -e: one missing file must not stop the capture

OUT=$HOME/tbt-capture-$(date +%Y%m%d-%H%M%S).txt
KLOG=${OUT%.txt}.klog
HERE=$(cd "$(dirname "$0")" && pwd)
DDC=/sys/kernel/debug/dynamic_debug/control
TR=/sys/kernel/tracing
TBDBG=/sys/kernel/debug/thunderbolt
MODS="thunderbolt thunderbolt_apple pcie_apple phy_apple_atc tps6598x dwc3_apple typec"
SPAM='Gen2/3 link error'

sec() { printf '\n===== %s\n' "$*"; }

# Print every small readable attribute file in a sysfs directory as name=value.
attrs() {
    local f
    for f in "$1"/*; do
        [[ -f $f && -r $f ]] || continue
        case ${f##*/} in uevent | nvm* | *key*) continue ;; esac
        printf '  %s=%s\n' "${f##*/}" "$(head -c 300 "$f" 2>/dev/null | tr '\n' ' ')"
    done
}

debug() { # $1 is +p or -p
    local m
    sudo test -w "$DDC" || return 0
    for m in $MODS; do echo "module $m $1" | sudo tee "$DDC" >/dev/null; done
}

# Kernel log since a marker: everything except the link-error flood, then the flood as
# a count per port and second.
log_since() {
    local mark=$1 tmp
    tmp=$(mktemp)
    sudo dmesg | awk -v m="$mark" 'f {print} index($0, m) {f = 1}' >"$tmp"
    grep -v "$SPAM" "$tmp" | tail -n 1500
    echo "--- link errors (count, second, port):"
    grep "$SPAM" "$tmp" |
        sed -E 's/^\[ *([0-9]+)\.[0-9]+\] [a-z-]+ ([0-9a-f]+\.cio).*lane=([01]).*/\1 \2 lane\3/' |
        sort | uniq -c
    rm -f "$tmp"
}

state() {
    sec "$1: thunderbolt devices"
    for d in /sys/bus/thunderbolt/devices/*; do
        [[ -e $d ]] || continue
        echo "${d##*/}"
        attrs "$d"
    done

    sec "$1: thunderbolt debug registers"
    if sudo test -d "$TBDBG"; then
        for d in $(sudo sh -c "ls -d $TBDBG/*/ 2>/dev/null"); do
            echo "--- ${d}regs"
            sudo head -n 80 "${d}regs" 2>&1
            for p in $(sudo sh -c "ls -d ${d}port[12]/ 2>/dev/null"); do
                echo "--- ${p}regs"
                sudo head -n 40 "${p}regs" 2>&1
            done
        done
    else
        echo "no $TBDBG"
    fi

    sec "$1: type-c ports with a partner"
    for d in /sys/class/typec/*-partner /sys/class/typec/*-cable; do
        [[ -e $d ]] || continue
        echo "${d##*/}"
        attrs "$d"
        attrs "${d%-*}" | grep -E 'data_role|power_role|orientation|vconn_source|power_operation_mode'
    done

    sec "$1: pci behind the thunderbolt ports"
    lspci -D -nn 2>/dev/null | grep -v '^0000:' || echo "none (or no lspci)"
    for d in $(lspci -D 2>/dev/null | awk '$1 !~ /^0000:/ {print $1}' | head -n 12); do
        sudo lspci -D -vv -s "$d" 2>/dev/null | grep -E '^[0-9a-f]{4}:|LnkSta:|LnkCap:|Bus:|Memory behind|Prefetchable memory|Region|Kernel driver|Interrupt:|MSI'
    done
    grep -iE 'pcie|ahci' /proc/interrupts | awk '{print $1, $(NF-2), $(NF-1), $NF}' | head -n 40

    sec "$1: usb and disks"
    lsusb -t
    lsusb | grep -iE '174c|asmedia' || echo "no ASMedia USB device"
    lsblk -o NAME,TRAN,RO,SIZE,MODEL,FSTYPE
}

round() { # $1 label, $2 instruction for plugging in, $3 = eject to detach first
    local mark="tbt-capture $$ $1"
    echo
    if [[ ${3:-} == eject ]]; then
        echo "[$1] Detaching the disks first."
        {
            sec "$1: eject"
            "$HERE/tbt-kernel.sh" eject
        } 2>&1 | tee -a "$OUT"
        sync "$OUT"
        sleep 5
    fi
    echo "[$1] Unplug the enclosure from the Mac."
    read -r -p "        Press Enter when it is unplugged. "
    sleep 3
    echo | sudo tee "$TR/trace" >/dev/null 2>&1
    echo "$mark" | sudo tee /dev/kmsg >/dev/null
    echo "[$1] $2"
    read -r -p "        Wait about 30 seconds, then press Enter. "
    sleep 2
    {
        sec "$1: kernel log"
        log_since "$mark"
        sec "$1: port controller trace"
        sudo grep -v 'cd321x_irq: event=$' "$TR/trace" | tail -n 80
        state "$1"
    } >>"$OUT" 2>&1
    sync "$OUT"
}

case $(uname -r) in
*-tbtwip) ;;
*) echo "This is kernel $(uname -r), not the trial kernel. Run ./tbt-kernel.sh try, reboot, then this." >&2
    exit 1 ;;
esac

[[ -x $HERE/tbt-kernel.sh ]] || { echo "tbt-kernel.sh must be next to this script" >&2; exit 1; }

sudo -v || exit 1
trap 'debug -p; echo 0 | sudo tee "$TR/events/tps6598x/enable" >/dev/null 2>&1; sudo pkill -f "dmesg --follow-new" 2>/dev/null' EXIT

# New kernel messages, each one on disk before the next is read.
: >"$KLOG"
sudo dmesg --follow-new 2>/dev/null | while IFS= read -r line; do
    printf '%s\n' "$line" >>"$KLOG"
    sync "$KLOG"
done &

{
    sec "system"
    uname -r
    rpm -q m1n1
    tr -d '\0' </proc/device-tree/model
    echo
    echo "cable_info_or: $(cat /sys/module/thunderbolt_apple/parameters/cable_info_or 2>/dev/null || echo 'not in this build')"
    if sudo test -w "$DDC"; then
        echo "dynamic debug: available"
    else
        echo "dynamic debug: NOT available, driver debug lines will be missing"
    fi
} >"$OUT" 2>&1

echo
echo "Before starting: detaching the disks attached through PCIe over Thunderbolt."
"$HERE/tbt-kernel.sh" eject || exit 1
sleep 3
echo "Now unplug ALL the USB4 enclosures (leave the USB-A disks alone)."
read -r -p "        Press Enter when they are unplugged. "

sync "$OUT"
debug +p
echo 1 | sudo tee "$TR/events/tps6598x/enable" >/dev/null 2>&1
{
    echo "debug entries enabled: $(sudo grep -cE '\[(thunderbolt|thunderbolt_apple|phy_apple_atc|tps6598x)\].*=p' "$DDC" 2>/dev/null)"
} >>"$OUT" 2>&1

round "round1-as-usual" "Plug ONE enclosure into a REAR port, the way you normally do."
round "round2-eject-replug" "Plug the SAME enclosure into the SAME port again, the same way." eject

echo
echo "Done. Send this file: $OUT ($(wc -l <"$OUT") lines)"
echo "If the machine froze instead, send $KLOG after the next boot, and a photo of the screen."
