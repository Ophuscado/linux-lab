#!/usr/bin/env bash
# pmp.sh: the M2 Ultra's power management processor (PMP: memory and fabric DVFS by device votes, the die's fast
# temperature loop, the SMC and GPU channels), started by hand with lab copies of Asahi's driver. Nothing loads at
# boot: the device tree from 'tbt-kernel.sh dtb' with TBT_OVERLAYS="t6022-ane t6022-pmp" (kernel/dt/t6022-pmp.dts)
# gives m1n1 the pmp alias, so m1n1 copies the ADT's PMP settings into the node, and cuts the node's compatible so
# the stock pmp.ko never binds it.
#
# What runs it (4 Nov, on that tree, right after boot): build, votes, start --now; then dump shows the status word's
# bit 0 set and word 0 acknowledged. measure gives the numbers (KNOWLEDGE, Power management). A kernel with the lab's
# pmp series (src-patches/linux/pmp, in tbt-kernel.sh's default) starts it at boot instead, from the overlay's
# always-on request entries; then status, dump and measure are what is left here, and votes and start refuse.
#
#   kernel/pmp.sh build       pmp_votes.ko (kernel/pmp/pmp_votes.c) and pmp_lab.ko, pmp_lab_ro.ko (kernel/pmp/make_lab.py
#                             on the running kernel's drivers/soc/apple/pmp.rs) against the running kernel, into var/pmp
#   kernel/pmp.sh status      the running tree's pmp node (m1n1's settings there or not), the modules, and the report's
#                             8 request and acknowledge words (pmp_votes loaded read only and unloaded, or its dump)
#   kernel/pmp.sh bootargs    pmp_lab_ro: powers the PMP's island through the driver core, logs its boot arguments,
#                             writes nothing, starts nothing, refuses the device; unloaded after
#   kernel/pmp.sh votes       pmp_votes macos=1: word 0 as macOS has it when it starts the PMP (the P-CPU clusters, the
#                             GPU, the high bits; 4 Nov trace), which Linux's pmp-report cannot set; VOTES_DIE1=1 adds
#                             die1=1, die 1's display and fabric votes in word 1 (macOS wrote none that boot); held
#                             until 'unvotes' or reboot. VOTES_MASK=0x700 (say) sets only those of macOS's bits
#   kernel/pmp.sh start --now pmp_lab: patches BDID and DVID, starts the PMP's firmware and serves its messages. Needs
#                             'votes' first. There is no stop: the PMP runs until reboot
#   kernel/pmp.sh dump        the words again, through the loaded pmp_votes
#   kernel/pmp.sh unvotes     rmmod pmp_votes (words 0 and 1 back to what they were; word 0's added bits stay once the
#                             PMP runs)
#   kernel/pmp.sh measure LABEL [SECONDS]
#                             idle power and GPU read bandwidth, the same way with and without the PMP: waits up to
#                             10 min for the 1-minute load under 1, samples the SMC's Total System Power and 3.8 V rail
#                             each second for SECONDS (300), then vk-chain bw with the agxperf ICD under the GPU lock;
#                             MEASURE_BENCH=1 adds llama-compare's bench on llama2, qwen and gpt20 (MEASURE_BW=0 and
#                             MEASURE_WAIT=0 skip the bandwidth and the wait, for a dry run). Into
#                             var/pmp/measure-LABEL-<date>/, summary.txt first. No root
#
# Back to before: the stock tree (tbt-kernel.sh dtb without t6022-pmp, or previous-dt) and a reboot. The kernel log
# lines of every stage go to var/pmp/<stage>-<date>.log.
set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
OUT=$LAB/var/pmp
B=$OUT/build
mkdir -p "$OUT"
stamp=$(date +%Y%m%d-%H%M%S)
NODE=$(ls -d /proc/device-tree/soc@200000000/pmp@28e700000 2>/dev/null || true)

loaded() { grep -q "^$1 " /proc/modules; }
klog() {  # klog STAGE: this boot's kernel lines from the PMP, the report and the lab modules since the stage began
    journalctl -k -b --no-pager --since "@$t0" | grep -E 'pmp|apple_pmp|rtkit' | tee "$OUT/$1-$stamp.log" || true
}
ready() {  # the tree m1n1 filled in: the alias, the cut compatible, okay, its settings
    [[ -n $NODE ]] || die "no pmp node in the running tree"
    [[ $(tr -d '\0' <"$NODE/status") == okay ]] || die "the pmp node is not okay: boot the t6022-pmp tree (tbt-kernel.sh dtb)"
    [[ $(tr -d '\0' <"$NODE/compatible") == apple,t6020-pmp-v2 ]] || die "the pmp node keeps the stock compatible: not the t6022-pmp tree"
    [[ -e $NODE/apple,board-id ]] || die "no apple,board-id on the pmp node: m1n1 did not fill it"
}
need() { [[ -f $B/$1.ko ]] || die "no $1.ko: $0 build"; [[ $(modinfo -F vermagic "$B/$1.ko" | cut -d' ' -f1) == "$(uname -r)" ]] || die "$1.ko is for another kernel: $0 build"; }
t0=$(date +%s)

case ${1:-} in
build)
    K=/lib/modules/$(uname -r)/build
    [[ -f $K/drivers/soc/apple/pmp.rs ]] || die "no drivers/soc/apple/pmp.rs under $K"
    rm -rf "$B"; mkdir -p "$B"
    cp "$LAB/kernel/pmp/pmp_votes.c" "$B/"
    python3 -I "$LAB/kernel/pmp/make_lab.py" "$K/drivers/soc/apple/pmp.rs" "$B"
    echo 'obj-m += pmp_votes.o' >>"$B/Kbuild"
    make -s -C "$K" M="$B" modules >"$OUT/build-$stamp.log" 2>&1 || { tail -n 20 "$OUT/build-$stamp.log"; die "the modules did not build"; }
    for m in pmp_votes pmp_lab pmp_lab_ro; do echo "$m: $(modinfo -F vermagic "$B/$m.ko")"; done
    ;;
status)
    if [[ -n $NODE ]]; then
        echo "pmp node: status $(tr -d '\0' <"$NODE/status"), compatible $(tr '\0' ' ' <"$NODE/compatible")"
        echo "  m1n1's settings: $(compgen -G "$NODE/apple,tunable-*" | wc -l) apple,tunable-*; board-id $([[ -e $NODE/apple,board-id ]] && echo set || echo absent); dram-capacity $([[ -e $NODE/apple,dram-capacity ]] && echo set || echo absent)"
    fi
    echo "alias pmp: $(tr -d '\0' </proc/device-tree/aliases/pmp 2>/dev/null || echo none)"
    echo "modules: $(for m in pmp pmp_lab pmp_lab_ro pmp_votes; do loaded $m && printf '%s ' $m; done)"
    if loaded pmp_votes; then echo 1 | sudo tee /sys/module/pmp_votes/parameters/dump >/dev/null
    else need pmp_votes; sudo insmod "$B/pmp_votes.ko" && sudo rmmod pmp_votes; fi
    klog status
    ;;
bootargs)
    ready; need pmp_lab_ro
    ! loaded pmp_lab || die "pmp_lab is loaded: the PMP already runs"
    sudo insmod "$B/pmp_lab_ro.ko"; sleep 1; sudo rmmod pmp_lab_ro
    klog bootargs
    ;;
votes)
    need pmp_votes
    ! loaded pmp_votes || die "pmp_votes is loaded already ($0 unvotes first)"
    ! loaded pmp || die "the kernel's own pmp driver has the PMP (the pmp series): its tree sets the request word"
    sync
    sudo insmod "$B/pmp_votes.ko" macos=1 ${VOTES_MASK:+mask=$VOTES_MASK} $([[ ${VOTES_DIE1:-0} == 1 ]] && echo die1=1)
    klog votes
    ;;
start)
    [[ ${2:-} == --now ]] || die "usage: $0 start --now   (the PMP runs until reboot; sync and stop the pool's writers first)"
    ready; need pmp_lab
    ! loaded pmp || die "the kernel's own pmp driver has the PMP (the pmp series): nothing to start"
    [[ $(cat /sys/module/pmp_votes/parameters/macos 2>/dev/null) == Y ]] || die "macOS's word 0 is not set: $0 votes"
    ! loaded pmp_lab || die "pmp_lab is loaded already"
    sync
    sudo insmod "$B/pmp_lab.ko"; sleep 3
    echo 1 | sudo tee /sys/module/pmp_votes/parameters/dump >/dev/null
    klog start
    echo "running when the status word's bit 0 is set and each request bit has its acknowledgement (log above)"
    ;;
dump)
    loaded pmp_votes || die "pmp_votes is not loaded: $0 status"
    echo 1 | sudo tee /sys/module/pmp_votes/parameters/dump >/dev/null
    klog dump
    ;;
unvotes)
    loaded pmp_votes || die "pmp_votes is not loaded"
    sudo rmmod pmp_votes
    klog unvotes
    ;;
measure)
    label=${2:?usage: $0 measure LABEL [SECONDS]}; secs=${3:-300}
    h=$(dirname "$(grep -l '^macsmc_hwmon$' /sys/class/hwmon/hwmon*/name | head -n 1)")
    pin() { local l; l=$(grep -l "^$1\$" "$h"/power*_label | head -n 1); echo "${l%_label}_input"; }
    total=$(pin 'Total System Power'); rail=$(pin '3.8 V Rail Power')
    [[ -r $total ]] || die "no Total System Power reading under $h"
    R=$OUT/measure-$label-$stamp; mkdir -p "$R"
    quiet=no
    for _ in $(seq "${MEASURE_WAIT:-60}"); do awk '{ exit !($1 < 1.0) }' /proc/loadavg && { quiet=yes; break; }; sleep 10; done
    pmp=off; loaded pmp_lab && pmp=on
    { echo "label $label; pmp $pmp; pmp_votes $(loaded pmp_votes && echo loaded || echo absent); quiet $quiet"
      echo "kernel $(uname -r); boot $(cat /proc/sys/kernel/random/boot_id); start $(date -u +%FT%TZ); load $(cut -d' ' -f1-3 /proc/loadavg)"; } >"$R/info.txt"
    echo "sampling power for $secs s (pmp $pmp, quiet $quiet)"
    printf 'unix\ttotal_uW\trail38_uW\tload1\n' >"$R/power.tsv"
    for _ in $(seq "$secs"); do
        printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$(cat "$total")" "$(cat "$rail" 2>/dev/null)" "$(cut -d' ' -f1 /proc/loadavg)" >>"$R/power.tsv"
        sleep 1
    done
    icd=$(compgen -G "$LAB/build/mesa-side/agxperf/share/vulkan/icd.d/asahi_icd.*.json" | head -n 1 || true)
    lock=$HOME/.cache/linux-lab-gpu.lock
    if [[ ${MEASURE_BW:-1} == 0 ]]; then echo "bandwidth skipped (MEASURE_BW=0)" >"$R/bw.txt"
    elif [[ -n $icd ]]; then
        { exec 9>>"$lock"; } 2>/dev/null || exec 9<"$lock"
        flock 9; nice -n 10 "$LAB/gpu/vk-chain/vk-chain.sh" bw "$icd" >"$R/bw.txt" 2>&1 || echo "vk-chain bw failed" >>"$R/bw.txt"; flock -u 9
    else echo "no agxperf ICD under $LAB/build/mesa-side: bandwidth skipped" >"$R/bw.txt"; fi
    [[ ${MEASURE_BENCH:-0} != 1 ]] || STEPS=bench COMPARE_OUT=$R nice -n 10 "$LAB/gpu/llama-compare.sh" llama2 qwen gpt20 >"$R/bench.txt" 2>&1 || true
    echo "end $(date -u +%FT%TZ); load $(cut -d' ' -f1-3 /proc/loadavg)" >>"$R/info.txt"
    { cat "$R/info.txt"
      awk -F'\t' 'NR > 1 { t[++n] = $2 / 1e6; s += $2 / 1e6; r += $3 / 1e6; l += $4 } END {
          asort(t); printf "power over %d s: mean %.2f W, median %.2f W, p10 %.2f W, p90 %.2f W; 3.8 V rail mean %.2f W; load mean %.2f\n",
              n, s / n, t[int(n / 2) + 1], t[int(n * 0.1) + 1], t[int(n * 0.9)], r / n, l / n }' "$R/power.tsv"
      grep -i -E 'GB/s' "$R/bw.txt" | tail -n 6 || true; } >"$R/summary.txt"
    cat "$R/summary.txt"
    ;;
*)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 2
    ;;
esac
