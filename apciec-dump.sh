#!/bin/bash
# apciec-dump.sh: run in macOS Terminal with one enclosure plugged in and mounted.
# Collects how macOS describes the Thunderbolt PCIe controller and what sits behind it,
# into ~/apciec.txt. Read-only: it only runs ioreg and system_profiler.
#
# Kept to the controller, router and PHY nodes on purpose, so the file does not carry the
# machine's serial number or network addresses. Lines naming a serial number are dropped.

OUT=$HOME/apciec.txt

sec() { printf '\n===== %s\n' "$*"; }

# Names of the device-tree nodes of interest, as macOS spells them on this machine.
names=$(ioreg -p IODeviceTree -w0 |
    sed -n 's/.*+-o \([^ @<]*\).*/\1/p' |
    grep -E '^(apciec|dart-apciec|acio|dart-acio|atc-phy)' | sort -u)

{
    sec "system"
    sw_vers
    sysctl -n hw.model

    sec "node names found"
    echo "$names"

    for n in $names; do
        sec "device tree: $n"
        ioreg -p IODeviceTree -r -l -w0 -n "$n" | grep -v -i 'serial'
    done

    # What macOS attached to each controller: driver classes, and for PCI devices their IDs.
    for n in $names; do
        case $n in apciec*) ;; *) continue ;; esac
        case $n in *piodma*) continue ;; esac
        sec "drivers and devices under: $n"
        ioreg -r -l -w0 -n "$n" |
            grep -E '\+-o |"(vendor-id|device-id|class-code|revision-id|IOName|name|compatible|IOClass|IOPCIExpressLinkStatus|IOPCIExpressLinkCapabilities|IOPCITunnelled|IOPCITunnelCompatible)" ='
    done

    sec "thunderbolt, as macOS reports it"
    system_profiler SPThunderboltDataType | grep -v -i 'serial\|UID'
} >"$OUT" 2>&1

echo "Wrote $OUT ($(wc -l <"$OUT" | tr -d ' ') lines). Attach it to the chat."
