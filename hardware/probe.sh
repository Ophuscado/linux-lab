#!/usr/bin/env bash
# hardware/probe.sh: this Mac as Linux sees it, into one folder, for comparison with macos/collect.sh and for
# later driver work without the machine at hand: the device tree, PCI and USB topology, Thunderbolt, the GPU
# through Vulkan, CPU frequencies and idle states, sensors, power domains, kernel config and modules.
# Values that identify the machine (serial numbers, MAC addresses, UUIDs of disks and boards) are left out.
#
#   hardware/probe.sh [OUT]     default var/probe/<host>-<kernel>-<date>; with sudo when it can (lspci's
#                               capabilities, the kernel log); prints the folder
set -uo pipefail
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OUT=${1:-$LAB/var/probe/$(hostname -s)-$(uname -r)-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
S=""; sudo -n true 2>/dev/null && S="sudo -n"
scrub() { grep -v -i -E 'serial|uuid|mac.?addr|wwn' |
    sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/gI; s/[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}/<uuid>/gI'; }
run() { local f=$1; shift; "$@" 2>&1 | scrub >"$OUT/$f"; }

# The device tree: every property as text (dtc), and the raw tree without the identifying properties.
if command -v dtc >/dev/null; then
    dtc -q -I fs -O dts /proc/device-tree 2>/dev/null | scrub >"$OUT/device-tree.dts"
fi
tar -C /proc -cf - device-tree 2>/dev/null | tar -C "$OUT" -xf - 2>/dev/null
find "$OUT/device-tree" -type f \( -iname '*serial*' -o -iname '*mac-address*' -o -iname '*uuid*' -o -name 'random-seed' \
    -o -name 'board-id' -o -name '*-nonce*' -o -name 'ecid' \) -delete 2>/dev/null
tar -C "$OUT" -czf "$OUT/device-tree.tar.gz" device-tree && rm -rf "$OUT/device-tree"

run cpuinfo.txt cat /proc/cpuinfo
run lscpu.txt lscpu -e=CPU,CORE,SOCKET,CLUSTER,MAXMHZ,MINMHZ
{ for p in /sys/devices/system/cpu/cpufreq/policy*; do
      echo "$(basename "$p") cpus=$(cat "$p/related_cpus") driver=$(cat "$p/scaling_driver") governor=$(cat "$p/scaling_governor")"
      echo "  frequencies: $(cat "$p/scaling_available_frequencies" 2>/dev/null)"
      [[ -d $p/stats ]] && echo "  time_in_state: $(tr '\n' ' ' <"$p/stats/time_in_state")"
  done
  for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do echo "idle $(cat "$s/name"): latency $(cat "$s/latency") us, residency $(cat "$s/residency") us"; done
} >"$OUT/cpufreq-idle.txt" 2>&1
run lspci.txt ${S:+$S} lspci -vvvnn
run lspci-tree.txt lspci -tvnn
run lsusb.txt lsusb -tv
run lsusb-verbose.txt lsusb -v
run boltctl.txt boltctl list
{ for d in /sys/bus/thunderbolt/devices/*; do
      echo "== $(basename "$d")"
      for a in vendor_name device_name generation rx_speed rx_lanes tx_speed tx_lanes nvm_version authorized link; do
          [[ -r $d/$a ]] && echo "  $a: $(cat "$d/$a" 2>/dev/null)"
      done
  done; } >"$OUT/thunderbolt-sysfs.txt" 2>&1
run vulkaninfo.txt vulkaninfo
for icd in "$LAB"/build/mesa-side/*/share/vulkan/icd.d/*.json; do
    [[ -f $icd ]] || continue
    n=$(basename "$(dirname "$(dirname "$(dirname "$(dirname "$icd")")")")")
    VK_DRIVER_FILES=$icd vulkaninfo 2>&1 | scrub >"$OUT/vulkaninfo-$n.txt"
done
{ for h in /sys/class/hwmon/hwmon*; do
      echo "== $(basename "$h") $(cat "$h/name" 2>/dev/null)"
      for f in "$h"/*_label; do [[ -f $f ]] && echo "  $(cat "$f"): $(cat "${f%_label}_input" 2>/dev/null)"; done
  done; } >"$OUT/hwmon.txt" 2>&1
{ for d in /sys/devices/platform/*/power /sys/bus/platform/devices/*/power; do
      [[ -r $d/runtime_status ]] && echo "$(basename "$(dirname "$d")") $(cat "$d/runtime_status") control=$(cat "$d/control" 2>/dev/null)"
  done | sort -u; } >"$OUT/runtime-pm.txt" 2>&1
[[ -n $S ]] && $S cat /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null >"$OUT/power-domains.txt"
run modules.txt lsmod
zcat /proc/config.gz 2>/dev/null >"$OUT/kernel-config.txt" || cp "/boot/config-$(uname -r)" "$OUT/kernel-config.txt" 2>/dev/null
run kernel-log.txt ${S:+$S} dmesg
run drm.txt bash -c 'for c in /sys/class/drm/*; do echo "$c $(cat $c/status 2>/dev/null) $(cat $c/modes 2>/dev/null | head -n 3 | tr "\n" " ")"; done'
run block.txt lsblk -o NAME,MODEL,SIZE,TRAN,ROTA,PHY-SEC,LOG-SEC,SCHED,RQ-SIZE,FSTYPE
run memory.txt bash -c 'cat /proc/meminfo; echo; getconf PAGESIZE'
[[ -x $LAB/system/power-dump.sh ]] && "$LAB/system/power-dump.sh" >"$OUT/power-dump.txt" 2>&1
{ echo "kernel $(uname -r)"; cat /etc/os-release; rpm -q mesa-vulkan-drivers m1n1 uboot-images-armv8 kernel 2>/dev/null; } >"$OUT/versions.txt"
tar -C "$(dirname "$OUT")" -czf "$OUT.tar.gz" "$(basename "$OUT")"
echo "$OUT ($(du -sh "$OUT" | cut -f1)), archive $OUT.tar.gz"
