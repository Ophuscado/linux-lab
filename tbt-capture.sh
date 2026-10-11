#!/usr/bin/env bash
# tbt-capture.sh (v2): record USB4 enclosure plug-ins on the trial kernel, with driver
# debug output switched on, into a single text file to send back.
#
# It only reads state and toggles kernel debug printing (switched off again at the end).
# Run it while booted into the 7.2.2-tbtwip kernel.
#
# v2: the router firmware logs about 30 identical link-error lines per second, which
# pushed everything else out of the v1 capture. They are now counted, not listed.

set -uo pipefail # deliberately not -e: one missing file must not stop the capture

OUT=$HOME/tbt-capture-$(date +%Y%m%d-%H%M%S).txt
DDC=/sys/kernel/debug/dynamic_debug/control
TR=/sys/kernel/tracing
TBDBG=/sys/kernel/debug/thunderbolt
MODS="thunderbolt thunderbolt_apple phy_apple_atc tps6598x dwc3_apple typec"
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

    sec "$1: usb and disks"
    lsusb -t
    lsusb | grep -iE '174c|asmedia' || echo "no ASMedia USB device"
    lsblk -o NAME,TRAN,SIZE,MODEL
}

round() { # $1 label, $2 instruction for plugging in
    local mark="tbt-capture $$ $1"
    echo
    echo "[$1] Unplug the enclosure from the Mac."
    read -r -p "        Press Enter when it is unplugged. "
    sleep 3
    echo | sudo tee "$TR/trace" >/dev/null 2>&1
    echo "$mark" | sudo tee /dev/kmsg >/dev/null
    echo "[$1] $2"
    read -r -p "        Wait about 20 seconds, then press Enter. "
    sleep 2
    {
        sec "$1: kernel log"
        log_since "$mark"
        sec "$1: port controller trace"
        sudo grep -v 'cd321x_irq: event=$' "$TR/trace" | tail -n 80
        state "$1"
    } >>"$OUT" 2>&1
}

case $(uname -r) in
*-tbtwip) ;;
*) echo "This is kernel $(uname -r), not the trial kernel. Run ./tbt-kernel.sh try, reboot, then this." >&2
    exit 1 ;;
esac

sudo -v || exit 1
trap 'debug -p; echo 0 | sudo tee "$TR/events/tps6598x/enable" >/dev/null 2>&1' EXIT

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
echo "Before starting: unplug ALL the USB4 enclosures (leave the USB-A disks alone)."
read -r -p "        Press Enter when they are unplugged. "

debug +p
echo 1 | sudo tee "$TR/events/tps6598x/enable" >/dev/null 2>&1
{
    echo "debug entries enabled: $(sudo grep -cE '\[(thunderbolt|thunderbolt_apple|phy_apple_atc|tps6598x)\].*=p' "$DDC" 2>/dev/null)"
} >>"$OUT" 2>&1

round "round1-as-usual" "Plug ONE enclosure into a REAR port, the way you normally do."
round "round2-plug-rotated" "Plug the SAME enclosure into the SAME port with the Mac-side plug rotated 180 degrees."

echo
echo "Done. Send this file: $OUT ($(wc -l <"$OUT") lines)"
