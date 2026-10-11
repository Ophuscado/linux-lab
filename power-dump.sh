#!/usr/bin/env bash
# power-dump.sh: how the running system is set up for power saving and speed, into
# ~/power-dump-<kernel release>.txt. It is the "before" for every tuning step: run it
# once idle with the enclosure attached and once without, so the cost of the enclosure
# and of the idle Thunderbolt controllers can be read from the power sensors.
# Read-only: it changes no setting and does not wake a sleeping disk. Lines with serial
# numbers or network addresses are dropped.

set -uo pipefail # deliberately not -e: one missing file must not stop the dump

OUT=$HOME/power-dump-$(uname -r).txt

sec() { printf '\n===== %s\n' "$*"; }
# Print "path: value" for every readable file given.
show() {
    local f
    for f in "$@"; do
        [[ -r $f ]] && printf '%s: %s\n' "$f" "$(tr '\n' ' ' <"$f" 2>/dev/null)"
    done
}

sudo -v || exit 1

{
    sec "system"
    uname -r
    cat /proc/cmdline
    uptime
    echo "tuned profile: $(tuned-adm active 2>/dev/null || echo 'tuned not running')"
    show /sys/power/mem_sleep /sys/power/state

    sec "cpu frequency and idle"
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d $p ]] || continue
        printf '%s cpus=%s governor=%s epp=%s cur=%s min=%s max=%s\n' "${p##*/}" \
            "$(cat "$p/affected_cpus" 2>/dev/null | tr ' ' ',')" "$(cat "$p/scaling_governor" 2>/dev/null)" \
            "$(cat "$p/energy_performance_preference" 2>/dev/null || echo -)" \
            "$(cat "$p/scaling_cur_freq" 2>/dev/null)" "$(cat "$p/scaling_min_freq" 2>/dev/null)" \
            "$(cat "$p/scaling_max_freq" 2>/dev/null)"
    done
    for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
        [[ -d $s ]] && printf 'cpu0 %s name=%s usage=%s time_us=%s disabled=%s\n' "${s##*/}" \
            "$(cat "$s/name")" "$(cat "$s/usage")" "$(cat "$s/time")" "$(cat "$s/disable")"
    done

    # Two readings ten seconds apart, so a steady idle figure can be told from a spike.
    sec "power, current and fan sensors"
    for round in 1 2; do
        echo "reading $round at $(date +%T)"
        for h in /sys/class/hwmon/hwmon*; do
            [[ -d $h ]] || continue
            for f in "$h"/power*_input "$h"/curr*_input "$h"/fan*_input; do
                [[ -r $f ]] || continue
                printf '  %s %s (%s) = %s\n' "$(cat "$h/name" 2>/dev/null)" "${f##*/}" \
                    "$(cat "${f%_input}_label" 2>/dev/null || echo -)" "$(cat "$f" 2>/dev/null)"
            done
        done
        [[ $round == 1 ]] && sleep 10
    done

    sec "power domains of the Thunderbolt ports"
    sudo cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | grep -iE '^domain|atc|pcie|acio|nhi|dart' ||
        echo "no pm_genpd_summary"

    sec "runtime power state of the Thunderbolt devices"
    for d in /sys/bus/platform/devices/*; do
        case ${d##*/} in *pcie* | *nhi* | *usb4* | *acio* | *cio* | *atcphy* | *.iommu | *.dart) ;; *) continue ;; esac
        printf '%s driver=%s runtime=%s control=%s\n' "${d##*/}" \
            "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)" \
            "$(cat "$d/power/runtime_status" 2>/dev/null)" "$(cat "$d/power/control" 2>/dev/null)"
    done

    # Link speed, width and the link power saving (ASPM, L1 substates) that each end offers
    # and has switched on, for everything behind the Thunderbolt PCIe controllers.
    sec "pci links behind the tunnels"
    for dev in /sys/bus/pci/devices/*; do
        b=${dev##*/}
        [[ $((16#${b%%:*})) -ge 8 ]] || continue
        printf '%s runtime=%s control=%s\n' "$b" "$(cat "$dev/power/runtime_status" 2>/dev/null)" \
            "$(cat "$dev/power/control" 2>/dev/null)"
        sudo lspci -vv -s "$b" 2>/dev/null | grep -E 'LnkCap:|LnkSta:|LnkCtl:|L1SubCap:|L1SubCtl1:|ASPM|Kernel driver' | sed 's/^[ \t]*/    /'
    done
    show /sys/module/pcie_aspm/parameters/policy

    sec "sata link power"
    for h in /sys/class/scsi_host/host*; do
        [[ -r $h/link_power_management_policy ]] &&
            printf '%s (%s): %s\n' "${h##*/}" "$(readlink -f "$h" | grep -o '[0-9a-f]*\.pcie\|usb[0-9]*' | head -n 1)" \
                "$(cat "$h/link_power_management_policy")"
    done

    sec "disks"
    lsblk -d -o NAME,TRAN,ROTA,RO,SIZE,MODEL,SCHED,RA,RQ-SIZE 2>/dev/null
    for q in /sys/block/sd*/queue; do
        [[ -d $q ]] || continue
        d=${q%/queue}
        d=${d##*/}
        printf '%s scheduler=[%s] read_ahead_kb=%s max_sectors_kb=%s nr_requests=%s queue_depth=%s' "$d" \
            "$(grep -o '\[.*\]' "$q/scheduler" 2>/dev/null | tr -d '[]')" "$(cat "$q/read_ahead_kb")" \
            "$(cat "$q/max_sectors_kb")" "$(cat "$q/nr_requests")" "$(cat "/sys/block/$d/device/queue_depth" 2>/dev/null)"
        # "Check power mode" does not spin a disk up.
        if command -v hdparm >/dev/null; then
            printf ' state=%s' "$(sudo hdparm -C "/dev/$d" 2>&1 | sed -n 's/.*drive state is: *//p')"
        else
            printf ' state=(hdparm not installed)'
        fi
        echo
    done
    echo "hd-idle: $(systemctl is-active hd-idle 2>/dev/null || true) $(rpm -q hd-idle 2>/dev/null || true)"

    sec "usb power"
    for u in /sys/bus/usb/devices/*; do
        [[ -r $u/product ]] || continue
        printf '%s %s speed=%s control=%s runtime=%s\n' "${u##*/}" "$(cat "$u/product")" "$(cat "$u/speed" 2>/dev/null)" \
            "$(cat "$u/power/control" 2>/dev/null)" "$(cat "$u/power/runtime_status" 2>/dev/null)"
    done

    sec "interrupts of the tunnel and its disks"
    grep -E 'CPU0|ahci|pcie|PCIe|nhi|thunderbolt' /proc/interrupts | cut -c1-240

    sec "bluetooth and suspend"
    rfkill 2>/dev/null
    lsmod | grep -E '^(hci_bcm4377|bluetooth|btbcm) '
    echo "suspends in this boot: $(sudo journalctl -k -b --no-pager -o cat 2>/dev/null | grep -c 'PM: suspend entry')"
    # What the Bluetooth controller logged around each suspend and resume.
    sudo journalctl -k -b --no-pager -o short-monotonic 2>/dev/null |
        grep -E 'PM: suspend (entry|exit)|hci0|Bluetooth:|bcm4377' | tail -n 60
    systemctl is-enabled asahi-btsync.service 2>&1 | sed 's/^/asahi-btsync.service: /'

    sec "memory"
    free -m
    swapon --show 2>/dev/null

    sec "gpu and vulkan"
    lsmod | grep -E '^(asahi|apple_dcp|appledrm) ' || echo "no asahi GPU module loaded"
    rpm -q mesa-vulkan-drivers mesa-dri-drivers 2>/dev/null
    if command -v vulkaninfo >/dev/null; then
        vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverName|driverInfo|apiVersion|deviceType'
        vulkaninfo 2>/dev/null | grep -E 'VK_KHR_cooperative_matrix|shaderFloat16|shaderInt8|shaderIntegerDotProduct |storageBuffer16BitAccess|heapBudget|size  *=' | sort | uniq -c | head -n 30
    else
        echo "vulkaninfo not installed (package vulkan-tools)"
    fi
} 2>&1 | grep -viE 'serial|([0-9a-f]{2}:){5}[0-9a-f]{2}' >"$OUT"

echo "Wrote $OUT ($(wc -l <"$OUT") lines). Attach it to the chat."
