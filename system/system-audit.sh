#!/usr/bin/env bash
# system-audit.sh: one read-only look at the whole machine, to find what is broken, missing or
# untuned: boot and firmware, failed units and logged errors, CPU, memory, power and heat,
# storage health, network and firewall, the desktop session (GPU, display, audio, Bluetooth),
# compatibility layers (x86 emulation, 4K-page VM, Flatpak), security, updates and timers.
#
#   sudo ./system-audit.sh [OUT]     default OUT ~/migrate/audit/system-audit-<date>.txt
#
# Read-only: it changes no setting, starts nothing, and does not touch the enclosure disks (no
# SMART on them, which would wake a sleeping one). The desktop's own state is read as you, in
# your session. Lines with serial numbers, MAC or IP addresses are dropped or masked.

set -uo pipefail # deliberately not -e: one missing tool must not stop the audit

[[ $EUID == 0 && -n ${SUDO_USER:-} ]] || { echo "run it as: sudo $0" >&2; exit 1; }
U=$SUDO_USER
UHOME=$(getent passwd "$U" | cut -d: -f6)
UID_=$(id -u "$U")
OUT=${1:-$UHOME/migrate/audit/system-audit-$(date +%Y%m%d-%H%M).txt}
mkdir -p "$(dirname "$OUT")"

sec() { printf '\n===== %s\n' "$*"; }
# run CMD...: the command line, then its output (at most 20 s), or why there is none.
run() {
    printf -- '--- %s\n' "$*"
    if ! command -v "$1" >/dev/null 2>&1; then echo "(not installed: $1)"; return; fi
    timeout -k 5 20 "$@" 2>&1 | head -n "${LINES_MAX:-60}"
}
# as_user CMD...: the same, inside the desktop user's session.
as_user() {
    printf -- '--- (as %s) %s\n' "$U" "$*"
    if ! command -v "$1" >/dev/null 2>&1; then echo "(not installed: $1)"; return; fi
    timeout -k 5 20 runuser -u "$U" -- env XDG_RUNTIME_DIR=/run/user/$UID_ \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$UID_/bus WAYLAND_DISPLAY=wayland-0 "$@" 2>&1 |
        head -n "${LINES_MAX:-60}"
}
# states VERB UNIT...: "unit: state" for each unit (systemctl is-active or is-enabled).
states() { local v=$1 u; shift; for u in "$@"; do printf '%s: %s\n' "$u" "$(systemctl "$v" "$u" 2>&1 | head -n 1)"; done; }
show() { local f; for f in "$@"; do [[ -r $f ]] && printf '%s: %s\n' "$f" "$(tr '\0\n' '  ' <"$f" 2>/dev/null)"; done; }
mask() {
    sed -E -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]+)?\b/<ip4>/g' \
        -e 's/\b[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4})*::([0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4})*)?(\/[0-9]+)?/<ip6>/g' \
        -e 's/\b([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}(\/[0-9]+)?/<ip6>/g' \
        -e '/[Ss]erial [Nn]umber|ID_SERIAL|serial_number|SerialNumber/d'
}

{
    echo "system-audit $(date '+%F %T %Z') on $(hostname)"

    sec "system and boot"
    cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID)='
    uname -a
    cat /proc/cmdline
    uptime
    run journalctl --list-boots --no-pager -q
    for f in system-fw-version os-fw-version m1n1-stage2-version; do
        printf 'asahi,%s: %s\n' "$f" "$(tr -d '\0' </proc/device-tree/chosen/asahi,$f 2>/dev/null)"
    done
    tr -d '\0' </proc/device-tree/compatible 2>/dev/null | tr '\0' ' '; echo
    echo "page size: $(getconf PAGESIZE)  kernel taint: $(cat /proc/sys/kernel/tainted)"
    echo "kernels installed:"; rpm -q kernel kernel-16k kernel-core 2>/dev/null | grep -v 'not installed'
    run grubby --default-kernel

    sec "packages that matter on Asahi"
    rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' 2>/dev/null | sort | grep -E \
        '^(asahi-|m1n1|uboot-images|speakersafetyd|alsa-ucm-asahi|mesa-(vulkan|dri|libGL)|tuned|power-profiles|zram|systemd-oomd|earlyoom|fex|muvm|box64|steam|widevine|smartmontools|nvme-cli|restic|mergerfs|snapraid|firewalld|dnf-automatic|fwupd|tlp|thermald|lm_sensors|hdparm|irqbalance|btrfs-progs|snapper|flatpak |podman |toolbox|kernel-tools|perf )' |
        head -n 80

    sec "health: failed units, errors since boot, crashes"
    run systemctl --failed --no-pager --plain
    as_user systemctl --user --failed --no-pager --plain
    echo "--- errors since boot, by unit (journal priority err and worse):"
    journalctl -b -p err --no-pager -o json 2>/dev/null | python3 -c '
import json, sys, collections
c = collections.Counter()
for l in sys.stdin:
    try: e = json.loads(l)
    except Exception: continue
    c[e.get("_SYSTEMD_UNIT") or e.get("SYSLOG_IDENTIFIER") or "?"] += 1
for k, v in c.most_common(25): print("%6d %s" % (v, k))'
    echo "--- the last distinct error lines (kernel lines about the enclosure disks left out):"
    journalctl -b -p err --no-pager -o cat 2>/dev/null | grep -vE '^\[?sd [0-9]|I/O error, dev sd|ata[0-9]+' |
        sed -E 's/[0-9]+/N/g' | awk '!seen[$0]++' | tail -n 40
    echo "--- kernel warnings and errors, distinct (numbers folded):"
    dmesg -l err,warn 2>/dev/null | sed -E 's/^\[[ 0-9.]+\] //; s/[0-9]+/N/g' | awk '!seen[$0]++' | tail -n 60
    run coredumpctl list --since=-7d --no-pager
    echo "--- out-of-memory kills this boot: $(journalctl -b -k --no-pager -o cat 2>/dev/null | grep -c 'Out of memory: Killed')"

    sec "CPU, power and heat"
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d $p ]] || continue
        printf '%s cpus=%s driver=%s governor=%s cur=%s min=%s max=%s\n' "${p##*/}" "$(cat "$p/related_cpus")" \
            "$(cat "$p/scaling_driver")" "$(cat "$p/scaling_governor")" "$(cat "$p/scaling_cur_freq")" \
            "$(cat "$p/scaling_min_freq")" "$(cat "$p/cpuinfo_max_freq")"
    done
    echo "cpuidle driver: $(cat /sys/devices/system/cpu/cpuidle/current_driver 2>/dev/null), governor: $(cat /sys/devices/system/cpu/cpuidle/current_governor 2>/dev/null)"
    run tuned-adm active
    run powerprofilesctl get
    show /sys/power/mem_sleep /sys/power/state
    for h in /sys/class/hwmon/hwmon*; do
        n=$(cat "$h/name" 2>/dev/null)
        for t in "$h"/{temp,power,fan,in,curr}*_input; do
            [[ -r $t ]] || continue
            l=$(cat "${t%_input}_label" 2>/dev/null || basename "$t")
            printf '%s %s = %s\n' "$n" "$l" "$(cat "$t")"
        done
    done | head -n 80
    show /sys/class/thermal/thermal_zone*/type

    sec "memory"
    free -h
    run zramctl
    run swapon --show
    sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.dirty_bytes vm.dirty_background_bytes \
        vm.overcommit_memory vm.vfs_cache_pressure vm.min_free_kbytes vm.watermark_scale_factor kernel.dmesg_restrict 2>&1
    show /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag /sys/kernel/mm/lru_gen/enabled
    states is-active systemd-oomd earlyoom
    run oomctl
    grep -E '^(MemTotal|MemAvailable|Dirty|Writeback|AnonPages|Shmem|SwapTotal|SwapFree|Hugepagesize):' /proc/meminfo

    sec "storage: system disk and filesystems"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL /dev/nvme0n1 2>/dev/null
    findmnt -t btrfs,vfat,ext4,xfs -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -v '/migrate/'
    run btrfs filesystem usage -T /
    run btrfs device stats /
    run btrfs scrub status /
    run smartctl -a /dev/nvme0
    run nvme smart-log /dev/nvme0
    states is-enabled fstrim.timer smartd.service btrfs-scrub@-.timer snapper-timeline.timer
    echo "--- I/O schedulers in use:"; cat /sys/block/*/queue/scheduler 2>/dev/null | sort | uniq -c
    echo "--- disks on each transport:"; lsblk -dno TRAN 2>/dev/null | sort | uniq -c
    echo "--- local udev rules and sysctl files:"; ls -l /etc/udev/rules.d /etc/sysctl.d 2>/dev/null
    echo "--- mergerfs and the migration's tmux sessions:"; mergerfs --version 2>&1 | head -n 1; tmux ls 2>&1

    sec "network"
    ip -br link | mask
    ip -br addr | mask
    for d in /sys/class/net/*; do
        i=${d##*/}
        [[ -e $d/device ]] || continue
        printf '%s driver=%s speed=%s duplex=%s mtu=%s\n' "$i" "$(basename "$(readlink -f /sys/class/net/$i/device/driver)" 2>/dev/null)" \
            "$(cat /sys/class/net/$i/speed 2>/dev/null)" "$(cat /sys/class/net/$i/duplex 2>/dev/null)" "$(cat /sys/class/net/$i/mtu)"
    done
    run iw dev
    run nmcli -t -f NAME,TYPE,DEVICE,AUTOCONNECT connection show
    run firewall-cmd --state
    run firewall-cmd --get-active-zones
    run firewall-cmd --list-all
    echo "--- listening sockets:"; ss -Htulpn 2>/dev/null | awk '{print $1, $5, $7}' | mask | sort -u | head -n 50
    states is-active sshd cockpit.socket avahi-daemon cups
    run timedatectl show -p NTPSynchronized -p TimeUSec -p Timezone
    run resolvectl status --no-pager

    sec "desktop session: GPU, display, audio, Bluetooth, input"
    as_user loginctl list-sessions --no-pager
    echo "session type: $(loginctl show-session "$(loginctl list-sessions --no-legend | awk -v u="$U" '$3 == u {print $1; exit}')" -p Type --value 2>/dev/null)"
    as_user plasmashell --version
    as_user vulkaninfo --summary
    as_user eglinfo -B
    as_user kscreen-doctor -o
    show /sys/class/drm/card*-*/status
    as_user wpctl status
    states is-active speakersafetyd
    run bluetoothctl show
    run bluetoothctl devices
    echo "--- recent Bluetooth errors:"; journalctl -b -u bluetooth --no-pager -o cat -p warning 2>/dev/null | sed -E 's/[0-9]+/N/g' | awk '!seen[$0]++' | tail -n 15
    echo "--- input devices:"; grep -E '^N: Name=' /proc/bus/input/devices | sort | uniq -c

    sec "compatibility layers"
    printf 'binfmt handlers:'; for f in /proc/sys/fs/binfmt_misc/*; do [[ ${f##*/} =~ ^(register|status|\*)$ ]] || printf ' %s' "${f##*/}"; done; echo
    run muvm --help
    run FEXInterpreter --version
    run box64 --version
    as_user flatpak list --app --columns=application,version,origin
    run flatpak remotes
    run podman --version
    [[ -e /dev/kvm ]] && echo "/dev/kvm present" || echo "no /dev/kvm"

    sec "security"
    run getenforce
    run sestatus
    echo "--- sudoers drop-ins:"; ls -l /etc/sudoers.d 2>/dev/null
    grep -rhE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | sed 's/^/    NOPASSWD: /'
    echo "wheel: $(getent group wheel | cut -d: -f4)"
    echo "--- accounts with a password or shell:"; awk -F: '$7 !~ /(nologin|false)$/ {print $1, $3, $7}' /etc/passwd
    echo "--- ssh: $(systemctl is-enabled sshd 2>&1); keys: $(ls "$UHOME/.ssh" 2>/dev/null | tr '\n' ' ')"
    stat -c '%a %U %n' "$UHOME" "$UHOME/.ssh" "$UHOME/.config/restic" "$UHOME/.config/restic/password" 2>/dev/null

    sec "updates, timers, enabled services"
    echo "--- updates waiting (dnf check-update):"
    timeout -k 5 120 dnf -q check-update 2>&1 | head -n 100
    echo "dnf check-update code ${PIPESTATUS[0]} (100: updates waiting, 0: none)"
    run dnf history list --reverse
    run systemctl list-timers --all --no-pager
    as_user systemctl --user list-timers --all --no-pager
    echo "--- enabled system services:"; systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' '; echo
    echo "--- enabled user services:"; runuser -u "$U" -- env XDG_RUNTIME_DIR=/run/user/$UID_ systemctl --user list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' '; echo
    run fwupdmgr get-devices --no-unreported-check
} 2>&1 | mask >"$OUT"

chown "$U": "$OUT" "$(dirname "$OUT")"
echo "written: $OUT ($(wc -l <"$OUT") lines)"
