#!/usr/bin/env bash
# ane.sh: the M2 Ultra's Neural Engine (die 0) through omarchy-ane, by the stages of its docs/ultra-test-runbook.md,
# from the lab's checkout src/linux-ane (github.com/Ophuscado/linux-ane). Nothing loads at boot: the trial kernel's
# device tree carries the ANE node (tbt-kernel.sh, TBT_OVERLAYS=t6022-ane), and the driver is loaded by hand here.
#
#   kernel/ane.sh probe       stage 0: omarchy-ane-probe (device tree and /proc only), JSON into var/ane/
#   kernel/ane.sh build       the ane_t6021 module against the running kernel, libane and the tools (user)
#   kernel/ane.sh firmware    omarchy-ane-firmware-fetch: about 5 MB of the macOS 13.5 restore image from Apple's CDN,
#                             installed under /usr/lib/firmware/apple/ane only when size and SHA-256 match its pin
#   kernel/ane.sh load        insmod the module built above (not installed, so it never loads at boot)
#   kernel/ane.sh check       omarchy-ane-check and the smoke run (20 adds, bit-exact against the golden)
#   kernel/ane.sh deep [--submit]
#                             omarchy-mlx's collector with its ANE smoke (scripts/collect_deep.py --ane-smoke), the
#                             judged row upstream asks for to enable the M2 Ultra by default: src/omarchy-mlx (cloned
#                             when missing), this checkout's check and smoke tools on PATH, the driver loaded, the
#                             machine idle (it waits up to 5 min for load < 0.5). omarchy-ane-check wants the module
#                             where modinfo finds it, so for the run it sits in updates/ with a blacklist line (no
#                             load at boot), both removed after. Writes var/ane/deep-<date>.tgz and its
#                             .submission.md, redacted, uploads nothing; --submit also sends them (public receipt)
#   kernel/ane.sh unload      rmmod
#   kernel/ane.sh report      everything the runbook asks to send back, into var/ane/report-<date>/
#   kernel/ane.sh autoload on|off|status
#                             load the module after each boot (a late oneshot unit, never in the initramfs or
#                             modules-load.d, so a hang cannot hold the boot): the module built above is copied to
#                             /usr/local/lib/ane/<release>/ and loaded only on that kernel and when the running
#                             device tree has the ANE node. Off by default: the driver pins itself until reboot and
#                             keeps the ANE from napping, and every kernel build needs a new 'build' and 'autoload on'.
#
# The runbook's stop rule applies: a stage that hangs over 60 s means a power cycle, and the same stage is not
# retried twice in a row; a refusal by the driver is a result, kept verbatim.
set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
A=$LAB/src/linux-ane
OUT=$LAB/var/ane
[[ -d $A/.git ]] || die "no checkout at $A: git clone https://github.com/Ophuscado/linux-ane $A"
mkdir -p "$OUT"
MOD=$A/ane/t6021/ane_t6021.ko
stamp=$(date +%Y%m%d-%H%M%S)

case ${1:-} in
probe)
    python3 -I "$A/tools/omarchy-ane-probe" --pretty >"$OUT/probe-$stamp.json"
    echo "$OUT/probe-$stamp.json"
    ;;
build)
    [[ -d /lib/modules/$(uname -r)/build ]] || die "no build tree for $(uname -r) (tbt-kernel.sh install links it)"
    make -C "$A/ane/t6021" >"$OUT/build-$stamp.log" 2>&1 || { tail -n 20 "$OUT/build-$stamp.log"; die "the module did not build"; }
    make -C "$A/libane" >>"$OUT/build-$stamp.log" 2>&1 || { tail -n 20 "$OUT/build-$stamp.log"; die "libane did not build"; }
    make -C "$A/tools" >>"$OUT/build-$stamp.log" 2>&1 || echo "WARN: the tools did not all build (see $OUT/build-$stamp.log)"
    modinfo "$MOD" | grep -E '^(version|srcversion|vermagic|alias)' | head -n 8
    ;;
firmware)
    sudo python3 -I "$A/packaging/omarchy-ane-firmware-fetch" | tee "$OUT/firmware-$stamp.log"
    python3 -I "$A/packaging/omarchy-ane-firmware-fetch" --check | tee -a "$OUT/firmware-$stamp.log"
    ;;
load)
    [[ -f $MOD ]] || die "no module: $0 build"
    # The SoC node is /soc@200000000 in the running tree (the overlays name it /soc, which fdtoverlay resolves).
    grep -q -a 'apple,t6022-ane' /proc/device-tree/soc*/ane@284000000/compatible 2>/dev/null ||
        die "no ANE node in the running device tree: boot the trial kernel built with TBT_OVERLAYS=t6022-ane"
    lsmod | grep -q '^ane_t6021 ' && { echo "ane_t6021 is loaded already"; exit 0; }
    sudo insmod "$MOD"
    sleep 2
    journalctl -k -b --no-pager | grep -i -E 'ane|dart' | tail -n 20
    ls -l /dev/accel/ 2>/dev/null || echo "no /dev/accel node"
    ;;
check)
    bash "$A/packaging/omarchy-ane-check" | tee "$OUT/check-$stamp.txt" || true
    python3 -I "$A/packaging/omarchy-ane-smoke" --timeout 120 | tee "$OUT/smoke-$stamp.json"
    ;;
deep)
    M=$LAB/src/omarchy-mlx
    [[ -d $M/.git ]] || git clone -q --depth 1 https://github.com/joshuaswarren/omarchy-mlx "$M"
    lsmod | grep -q '^ane_t6021 ' || die "the driver is not loaded: kernel/ane.sh load"
    U=/usr/lib/modules/$(uname -r)/updates/ane_t6021.ko BL=/etc/modprobe.d/ane-lab-noautoload.conf
    trap 'sudo rm -f "$U" "$BL"; sudo depmod -a' EXIT
    echo 'blacklist ane_t6021' | sudo tee "$BL" >/dev/null
    sudo install -D -m 644 "$MOD" "$U" && sudo depmod -a
    echo "omarchy-mlx $(git -C "$M" log -1 --format='%h %cs'), linux-ane $(git -C "$A" log -1 --format='%h %cs'), load $(cut -d' ' -f1-3 /proc/loadavg), CPU PSI $(sed -n 's/^some avg10=\([^ ]*\).*/\1/p' /proc/pressure/cpu)"
    # What keeps the load up: tasks running (R) or waiting on I/O (D), counted by name.
    ps -eo stat=,comm= | awk '$1 ~ /^[RD]/ { n[$1 " " $2]++ } END { for (k in n) print "  " n[k], k }' | sort -rn | head -n 8
    PATH=$A/packaging:$PATH python3 "$M/scripts/collect_deep.py" --ane-smoke --out "$OUT/deep-$stamp.tgz" "${@:2}"
    ;;
unload)
    sudo rmmod ane_t6021 && echo "unloaded"
    ;;
autoload)
    U=/etc/systemd/system/ane-autoload.service
    case ${2:-} in
    on)
        [[ -f $MOD ]] || die "no module: $0 build"
        v=$(modinfo -F vermagic "$MOD" | cut -d' ' -f1)
        [[ $v == "$(uname -r)" ]] || die "the module is built for $v, this kernel is $(uname -r): $0 build"
        sudo install -D -m 0644 "$MOD" "/usr/local/lib/ane/$v/ane_t6021.ko"
        # $$ is a literal $ for systemd, so the shell gets $(uname -r) and $m.
        printf '%s\n' '[Unit]' 'Description=Neural Engine driver (ane_t6021), loaded after boot' 'After=multi-user.target' '' \
            '[Service]' 'Type=oneshot' 'RemainAfterExit=yes' 'TimeoutStartSec=60' \
            "ExecStart=/bin/sh -c 'm=/usr/local/lib/ane/\$\$(uname -r)/ane_t6021.ko; [ -f \$\$m ] || exit 0; grep -q -a apple,t6022-ane /proc/device-tree/soc*/ane@284000000/compatible 2>/dev/null || exit 0; grep -q \"^ane_t6021 \" /proc/modules && exit 0; exec /usr/sbin/insmod \$\$m'" \
            '' '[Install]' 'WantedBy=multi-user.target' | sudo tee "$U" >/dev/null
        sudo systemctl daemon-reload && sudo systemctl enable ane-autoload.service
        echo "autoload on for $v (loads after the next boot; now: $(lsmod | grep -q '^ane_t6021 ' && echo loaded || echo 'not loaded: kernel/ane.sh load'))"
        ;;
    off)
        sudo systemctl disable ane-autoload.service 2>/dev/null || true
        sudo rm -f "$U"; sudo rm -rf /usr/local/lib/ane; sudo systemctl daemon-reload
        echo "autoload off (a module loaded now stays until reboot: it pins itself)"
        ;;
    status)
        echo "autoload: $(systemctl is-enabled ane-autoload.service 2>/dev/null || echo off); modules kept: $(ls /usr/local/lib/ane 2>/dev/null | tr '\n' ' ')"
        echo "loaded now: $(lsmod | grep -q '^ane_t6021 ' && echo yes || echo no)"
        ;;
    *) die "usage: $0 autoload on|off|status" ;;
    esac
    ;;
report)
    R=$OUT/report-$stamp; mkdir -p "$R"
    python3 -I "$A/tools/omarchy-ane-probe" --pretty >"$R/probe.json" 2>&1 || true
    bash "$A/packaging/omarchy-ane-check" >"$R/check.txt" 2>&1 || true
    journalctl -k -b --no-pager | grep -i -E 'ane|dart|mailbox|rtkit' | tail -n 80 >"$R/kernel.txt"
    ls -l /dev/accel/ >"$R/accel.txt" 2>&1 || true
    cp "$OUT"/smoke-*.json "$R/" 2>/dev/null || true
    { uname -r; git -C "$A" log -1 --format='linux-ane %H %s'; git -C "$LAB" log -1 --format='linux-lab %H %s'; } >"$R/versions.txt"
    echo "$R"
    ;;
*) die "usage: $0 probe|build|firmware|load|check|unload|report|autoload on|off|status" ;;
esac
