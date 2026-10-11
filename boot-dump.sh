#!/usr/bin/env bash
# boot-dump.sh: what the running kernel brought up, into ~/boot-<kernel release>.txt.
# Run it once on the stock kernel and once on the trial kernel, so the two can be compared.
# Read-only. Lines with serial numbers or network addresses are dropped.

set -uo pipefail # deliberately not -e: one missing file must not stop the dump

OUT=$HOME/boot-$(uname -r).txt
DT=/proc/device-tree

sec() { printf '\n===== %s\n' "$*"; }

sudo -v || exit 1

{
    sec "system"
    uname -r
    cat /proc/cmdline
    for f in iboot1-version iboot2-version system-fw-version os-fw-version m1n1-stage2-version; do
        printf '%s: ' "$f"
        tr -d '\0' <"$DT/chosen/asahi,$f" 2>/dev/null
        echo
    done

    # The controllers behind the Thunderbolt ports and what the bootloader filled in.
    sec "thunderbolt pcie nodes"
    for n in "$DT"/soc@*/pcie@*30000000; do
        [[ -d $n ]] || continue
        printf '%s status=%s domain=%s\n' "${n#"$DT"}" "$(tr -d '\0' <"$n/status" 2>/dev/null)" \
            "$(od -An -tu4 --endian=big "$n/linux,pci-domain" 2>/dev/null | tr -d ' ')"
        for p in "$n"/apple,tunable* "$n"/pci@0,0/apple,tunable*; do
            [[ -e $p ]] && printf '  %s: %s bytes\n' "${p#"$n"/}" "$(stat -c %s "$p")"
        done
    done
    for n in "$DT"/soc@*/cio@*; do
        [[ -e $n/apple,tunable-pcie-adapter ]] &&
            printf '%s apple,tunable-pcie-adapter: %s bytes\n' "${n#"$DT"}" \
                "$(stat -c %s "$n/apple,tunable-pcie-adapter")"
    done
    [[ -d /sys/class/thunderbolt_protocol_adapter ]] && ls /sys/class/thunderbolt_protocol_adapter

    sec "pci"
    lspci -D -nn 2>/dev/null || echo "no lspci"

    sec "deferred probes"
    sudo cat /sys/kernel/debug/devices_deferred

    sec "failed units"
    systemctl --failed --no-pager

    sec "modules"
    lsmod

    sec "kernel log"
    sudo dmesg
} 2>&1 | grep -viE 'serial|([0-9a-f]{2}:){5}[0-9a-f]{2}' >"$OUT"

echo "Wrote $OUT ($(wc -l <"$OUT") lines). Attach it to the chat."
