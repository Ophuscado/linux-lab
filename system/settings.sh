#!/usr/bin/env bash
# settings.sh: the standing settings of this machine, as one switch, each one a file this
# script owns and removes again.
#
#   settings.sh install [SPINDOWN_MIN]   everything below (default spin-down 30 min)
#   settings.sh uninstall                remove all of it
#   settings.sh status                   what is in force
#   settings.sh sleep-hook on|off|test   the suspend hook alone (see below)
#   settings.sh usb-cap on|off           the USB dirty cap alone (see below)
#   settings.sh indexer on|off           the file indexer kept off the data disks alone
#   settings.sh smartd-rescan on|off     SMART monitoring of disks that come after boot alone
#   settings.sh kernel-pin on|off        updates kept from replacing the kernel alone
#   settings.sh dirty-limit on|off       the cap on unwritten data for all disks alone
#   settings.sh smartd-quiet on|off      smartd wakes a sleeping disk once a day, not every 5 h
#   settings.sh no-llmnr on|off          no answers to LLMNR name queries from the network
#   settings.sh scrub on|off             a monthly btrfs scrub of the system disk
#   settings.sh quiet-services on|off    the services this Mac does not use, off
#   settings.sh flathub on|off           the Flathub app repository
#   settings.sh quiet-net on|off         no calls home the operator did not choose (below)
#   settings.sh firefox-quiet on|off     Firefox without telemetry, studies and ads (below)
#   settings.sh noatime on|off           noatime on the system disk's / and /home (btrfs)
#
# What "install" puts in place, and where it comes from:
#   authorize rule   tbt-disks.sh authorize on    USB4 devices are authorized as they appear
#                                                 (boltd mixes up the boxes' shared UUIDs)
#   spin-down rule   tbt-disks.sh spindown N      enclosure disks stand by after N minutes
#   mouse and paste  ux-fix.sh on                 no middle-click emulation, slower scroll,
#                                                 no primary-selection paste (KWin)
#   USB dirty cap    this script                  a USB disk holds at most 256 MiB of unwritten
#                                                 data, so a long copy onto a slow one no longer
#                                                 stalls every writer, sync and shutdown
#   indexer prune    this script                  the nightly plocate run skips the migration,
#                                                 the data and parity disks and the pool (it
#                                                 would walk millions of files and wake every
#                                                 disk each night); /etc/updatedb.conf, the
#                                                 original kept as updatedb.conf.settings-orig
#   smartd rescan    this script                  smartd looks for disks once, at boot, before
#                                                 the boxes are up, so it watched none of the
#                                                 32; a disk that appears arms a 90 s timer that
#                                                 makes smartd scan again (udev rule, timer, unit)
#   dirty limit      this script                  at most 4 GiB of unwritten data in memory for
#                                                 all disks (writeback starts at 1 GiB), instead
#                                                 of 20 % of the memory free, about 36 GB here:
#                                                 a box that drops loses less in flight, a flush
#                                                 or a shutdown waits seconds, not minutes; the
#                                                 disks write 1.4 GB/s at most, so nothing slows
#   kernel pin       this script                  dnf leaves the kernel-16k packages alone: a
#                                                 new one would become the default and point
#                                                 /boot/dtb at its own device trees, and the
#                                                 next boot would come up without the boxes;
#                                                 kernel/tbt-kernel.sh switches kernels by hand
#   smartd quiet     this script                  -n standby,48 in smartd.conf: a sleeping disk
#                                                 is checked after 48 skipped checks (a day),
#                                                 not 10 (5 h); the original kept beside it
#   no LLMNR         this script                  systemd-resolved stops answering name queries
#                                                 from the network on port 5355 (resolved.conf.d)
#   scrub            this script                  btrfs scrub of / once a month, idle I/O class
#   quiet services   this script                  VM guest agents (vmtoolsd, vgauthd,
#                                                 qemu-guest-agent), the md RAID monitor and its
#                                                 weekly check (no md RAID here), ModemManager
#                                                 (no modem): disabled; off puts Fedora's preset back
#   Flathub          this script                  the Flathub remote for Flatpak apps (system)
#   quiet net        this script                  NetworkManager's connectivity check (asks
#                                                 fedoraproject.org every 5 min) off; at login no
#                                                 geoclue demo agent, no Discover update notifier,
#                                                 no VM guest helpers (spice-vdagent, vmware-user:
#                                                 the Fedora KDE image brings them for VMs); ABRT
#                                                 keeps collecting crashes but sends none on its own
#                                                 (abrt-auto-reporting disabled: you review first).
#                                                 dnf's countme stays, the operator's choice
#   Firefox quiet    this script                  an enterprise policy: no telemetry, no studies
#                                                 (Normandy), no Pocket, no sponsored tiles,
#                                                 stories or suggestions, no AI chatbot sidebar;
#                                                 Fedora's own policies kept; nothing locked
#   SnapRAID timers  snapraid-setup.sh timers on  only once /etc/snapraid.conf exists
#   suspend hook     this script                  before sleep: unmount the pool and the
#                                                 enclosure disks and detach the tunneled PCIe
#                                                 devices; after resume: rescan and mount -a.
#                                                 UNTESTED on this machine: "install" leaves
#                                                 it off; "sleep-hook on" turns it on once
#                                                 you can try a suspend with the boxes on.
# The read-only rule of the migration (tbt-disks.sh readonly) is not a standing setting
# and is not touched here.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LAB=$(cd "$HERE/.." && pwd)
HOOK=${SETTINGS_HOOK:-/usr/lib/systemd/system-sleep/tbt-enclosures}
POOL=${SR_POOL:-/srv/pool}
ROOT=${SR_ROOT:-/mnt}

USB_RULE=${SETTINGS_USB_RULE:-/etc/udev/rules.d/62-usb-dirty-cap.rules}
USB_CAP=${SETTINGS_USB_CAP:-268435456}
INDEX_CONF=${SETTINGS_UPDATEDB:-/etc/updatedb.conf}
SMARTD_RULE=${SETTINGS_SMARTD_RULE:-/etc/udev/rules.d/63-smartd-rescan.rules}
UNITS=${SETTINGS_UNITS:-/etc/systemd/system}
PIN_CONF=${SETTINGS_PIN:-/etc/dnf/libdnf5.conf.d/60-linux-lab-kernel-pin.conf}
DIRTY_CONF=${SETTINGS_DIRTY:-/etc/sysctl.d/60-linux-lab-dirty.conf}
SMARTD_CONF=${SETTINGS_SMARTD_CONF:-/etc/smartmontools/smartd.conf}
LLMNR_CONF=${SETTINGS_LLMNR:-/etc/systemd/resolved.conf.d/60-linux-lab-no-llmnr.conf}
NM_CONF=${SETTINGS_NM:-/etc/NetworkManager/conf.d/60-linux-lab-no-connectivity-check.conf}
QUIET_AUTOSTART="geoclue-demo-agent.desktop org.kde.discover.notifier.desktop spice-vdagent.desktop vmware-user.desktop"
FF_POLICY=${SETTINGS_FF_POLICY:-/etc/firefox/policies/policies.json}
FF_DIST=${SETTINGS_FF_DIST:-/usr/lib64/firefox/distribution/policies.json}
QUIET_UNITS="vmtoolsd.service vgauthd.service qemu-guest-agent.service mdmonitor.service raid-check.timer ModemManager.service"
DIRTY_MAX=${SETTINGS_DIRTY_MAX:-4294967296}
DIRTY_BG=${SETTINGS_DIRTY_BG:-1073741824}
# The desktop user's home also under sudo (the migration lives there).
UHOME=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# The dirty cap of USB disks. A slow USB disk (the backup disk is a 5400 rpm 2.5" drive on
# usb-storage, one command at a time) could collect gigabytes of unwritten data in the page cache
# during a long copy: every writer on the machine was then throttled with it, and sync and shutdown
# waited hours for it. With strict_limit and max_bytes on its writeback device, at most USB_CAP
# bytes wait for it: the copy onto it slows to the disk's own speed, nothing else does.
usb_cap_now() { # on|off|status: every USB disk present now
    local d b n=0
    for d in /sys/block/sd*; do
        [[ -e $d && $(readlink -f "$d") == */usb[0-9]*/* ]] || continue
        b=/sys/class/bdi/$(cat "$d/dev")
        [[ -e $b/max_bytes && -e $b/strict_limit ]] || { echo "${d##*/}: this kernel has no per-disk cap"; continue; }
        if [[ $1 == on ]]; then
            echo "$USB_CAP" | sudo tee "$b/max_bytes" >/dev/null
            echo 1 | sudo tee "$b/strict_limit" >/dev/null
        elif [[ $1 == off ]]; then
            echo 100 | sudo tee "$b/max_ratio" >/dev/null
            echo 0 | sudo tee "$b/strict_limit" >/dev/null
        fi
        echo "${d##*/}: $(($(cat "$b/max_bytes") / 1048576)) MiB unwritten at most, strict $(cat "$b/strict_limit")"; n=$((n + 1))
    done
    ((n > 0)) || echo "no USB disk attached now"
}
usb_cap() {
    case $1 in
    on)
        printf '%s\n' \
            '# Written by settings.sh usb-cap on; removed by usb-cap off and by uninstall.' \
            '# A USB disk may hold at most this much unwritten data in the page cache (strict per-disk limit).' \
            "ACTION==\"add\", SUBSYSTEM==\"block\", ENV{DEVTYPE}==\"disk\", ENV{ID_BUS}==\"usb\", RUN+=\"/bin/sh -c 'echo $USB_CAP > /sys/class/bdi/%M:%m/max_bytes; echo 1 > /sys/class/bdi/%M:%m/strict_limit'\"" |
            sudo tee "$USB_RULE" >/dev/null
        sudo udevadm control --reload
        usb_cap_now on
        ;;
    off)
        sudo rm -f "$USB_RULE"
        sudo udevadm control --reload
        usb_cap_now off
        ;;
    esac
}

# Words added to PRUNEFS and PRUNEPATHS of updatedb.conf; off puts the original back.
indexer() {
    local fs="fuse.mergerfs hfsplus" paths="$UHOME/migrate $ROOT/data $ROOT/parity $POOL"
    case $1 in
    on)
        [[ -f $INDEX_CONF.settings-orig ]] || sudo cp -p "$INDEX_CONF" "$INDEX_CONF.settings-orig"
        sudo python3 -I - "$INDEX_CONF" "$fs" "$paths" <<'PY'
import re, sys
path, fs, paths = sys.argv[1], sys.argv[2].split(), sys.argv[3].split()
text = open(path).read()
def add(text, key, words):
    m = re.search(r'^%s\s*=\s*"([^"]*)"' % key, text, re.M)
    if not m:
        return text.rstrip("\n") + '\n%s = "%s"\n' % (key, " ".join(words))
    have = m.group(1).split()
    return text[:m.start(1)] + " ".join(have + [w for w in words if w not in have]) + text[m.end(1):]
open(path, "w").write(add(add(text, "PRUNEFS", fs), "PRUNEPATHS", paths))
PY
        echo "indexer: skips $fs and $paths"
        ;;
    off)
        if [[ -f $INDEX_CONF.settings-orig ]]; then sudo mv "$INDEX_CONF.settings-orig" "$INDEX_CONF"; fi
        echo "indexer: original $INDEX_CONF back"
        ;;
    status)
        if [[ -f $INDEX_CONF.settings-orig ]]; then
            # A path missing from PRUNEPATHS (a mount point renamed later, as /mnt/hd to /mnt/data on 28 Oct) is walked.
            local miss=() w; for w in $paths; do grep -Eq "^PRUNEPATHS *=.*[\" ]${w}[\" ]" "$INDEX_CONF" || miss+=("$w"); done
            echo "indexer prune: on ($INDEX_CONF)${miss:+; NOT pruned: ${miss[*]} (settings.sh indexer on adds them)}"
        else echo "indexer prune: off"; fi
        ;;
    esac
}
# udev arms smartd-rescan.timer when an ATA or SCSI disk appears; the timer is gone once it
# fired (RemainAfterElapse=no), so the next disk, or the next plug, arms it again.
smartd_rescan() {
    case $1 in
    on)
        printf '%s\n' '# Written by settings.sh smartd-rescan on; removed by smartd-rescan off and by uninstall.' \
            'ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_BUS}=="ata|scsi", TAG+="systemd", ENV{SYSTEMD_WANTS}+="smartd-rescan.timer"' |
            sudo tee "$SMARTD_RULE" >/dev/null
        printf '%s\n' '# Written by settings.sh smartd-rescan on.' '[Unit]' 'Description=Let smartd scan again for disks that came after boot' \
            '[Timer]' 'OnActiveSec=90' 'RemainAfterElapse=no' 'Unit=smartd-rescan.service' | sudo tee "$UNITS/smartd-rescan.timer" >/dev/null
        printf '%s\n' '# Written by settings.sh smartd-rescan on.' '[Unit]' 'Description=smartd scans for disks again' \
            '[Service]' 'Type=oneshot' 'ExecStart=/usr/bin/systemctl try-reload-or-restart smartd.service' | sudo tee "$UNITS/smartd-rescan.service" >/dev/null
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo udevadm control --reload 2>/dev/null || true
        sudo systemctl try-reload-or-restart smartd.service 2>/dev/null || true
        echo "smartd rescan: on; smartd scanned again now"
        ;;
    off)
        sudo rm -f "$SMARTD_RULE" "$UNITS/smartd-rescan.timer" "$UNITS/smartd-rescan.service"
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo udevadm control --reload 2>/dev/null || true
        echo "smartd rescan: off"
        ;;
    status)
        echo "smartd rescan: $([[ -f $SMARTD_RULE ]] && echo "on ($SMARTD_RULE)" || echo off); $(journalctl -u smartd -b --no-pager -o cat 2>/dev/null | grep -E '^Monitoring' | tail -n 1)"
        ;;
    esac
}
# The sysctl file for later boots, and the same values now; off goes back to the ratios
# Fedora sets (20 % and 10 %), which clears the byte values.
dirty_limit() {
    case $1 in
    on)
        printf '%s\n' '# Written by settings.sh dirty-limit on; removed by dirty-limit off and by uninstall.' \
            "vm.dirty_bytes = $DIRTY_MAX" "vm.dirty_background_bytes = $DIRTY_BG" | sudo tee "$DIRTY_CONF" >/dev/null
        sudo sysctl -q -p "$DIRTY_CONF" 2>/dev/null || true
        echo "dirty limit: on ($((DIRTY_MAX >> 20)) MiB, writeback from $((DIRTY_BG >> 20)) MiB)"
        # A per-disk cap is kept as a share of the global limit: set the USB one again.
        [[ ! -f $USB_RULE ]] || usb_cap_now on
        ;;
    off)
        sudo rm -f "$DIRTY_CONF"
        sudo sysctl -q -w vm.dirty_ratio=20 vm.dirty_background_ratio=10 2>/dev/null || true
        echo "dirty limit: off (20 % and 10 % of free memory)"
        ;;
    status)
        echo "dirty limit: $([[ -f $DIRTY_CONF ]] && echo "on ($DIRTY_CONF)" || echo off); now $(sysctl -n vm.dirty_bytes 2>/dev/null) bytes, ratio $(sysctl -n vm.dirty_ratio 2>/dev/null) %; dirty now $(awk '/^Dirty:/ {print int($2 / 1024)}' /proc/meminfo) MiB"
        ;;
    esac
}
smartd_quiet() {
    case $1 in
    on)
        [[ -f $SMARTD_CONF.settings-orig ]] || sudo cp -p "$SMARTD_CONF" "$SMARTD_CONF.settings-orig"
        sudo sed -i -E '/^DEVICESCAN/ s/-n standby,[0-9]+/-n standby,48/' "$SMARTD_CONF"
        sudo systemctl try-reload-or-restart smartd.service 2>/dev/null || true
        echo "smartd quiet: on ($(grep -m1 '^DEVICESCAN' "$SMARTD_CONF"))"
        ;;
    off)
        if [[ -f $SMARTD_CONF.settings-orig ]]; then sudo mv "$SMARTD_CONF.settings-orig" "$SMARTD_CONF"; fi
        sudo systemctl try-reload-or-restart smartd.service 2>/dev/null || true
        echo "smartd quiet: off"
        ;;
    status) echo "smartd quiet: $([[ -f $SMARTD_CONF.settings-orig ]] && echo on || echo off) ($(grep -m1 '^DEVICESCAN' "$SMARTD_CONF" 2>/dev/null))" ;;
    esac
}
no_llmnr() {
    case $1 in
    on)
        sudo mkdir -p "$(dirname "$LLMNR_CONF")"
        printf '%s\n' '# Written by settings.sh no-llmnr on; removed by no-llmnr off and by uninstall.' '[Resolve]' 'LLMNR=no' |
            sudo tee "$LLMNR_CONF" >/dev/null
        sudo systemctl try-reload-or-restart systemd-resolved.service 2>/dev/null || true
        echo "no LLMNR: on"
        ;;
    off)
        sudo rm -f "$LLMNR_CONF"
        sudo systemctl try-reload-or-restart systemd-resolved.service 2>/dev/null || true
        echo "no LLMNR: off"
        ;;
    status) echo "no LLMNR: $([[ -f $LLMNR_CONF ]] && echo on || echo off); listening on 5355: $(ss -Hlnu 2>/dev/null | grep -c ':5355 ')" ;;
    esac
}
scrub() {
    case $1 in
    on)
        printf '%s\n' '# Written by settings.sh scrub on; removed by scrub off and by uninstall.' '[Unit]' \
            'Description=Scrub the system disk (btrfs)' '[Service]' 'Type=oneshot' 'ExecStart=/usr/sbin/btrfs scrub start -B -c 3 /' |
            sudo tee "$UNITS/linux-lab-scrub.service" >/dev/null
        printf '%s\n' '# Written by settings.sh scrub on.' '[Unit]' 'Description=Monthly scrub of the system disk' \
            '[Timer]' 'OnCalendar=monthly' 'RandomizedDelaySec=6h' 'Persistent=true' '[Install]' 'WantedBy=timers.target' |
            sudo tee "$UNITS/linux-lab-scrub.timer" >/dev/null
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo systemctl enable --now linux-lab-scrub.timer 2>/dev/null || true
        echo "scrub: on (monthly; 'sudo systemctl start linux-lab-scrub' runs one now)"
        ;;
    off)
        sudo systemctl disable --now linux-lab-scrub.timer 2>/dev/null || true
        sudo rm -f "$UNITS/linux-lab-scrub.service" "$UNITS/linux-lab-scrub.timer"
        sudo systemctl daemon-reload 2>/dev/null || true
        echo "scrub: off"
        ;;
    status) echo "scrub: $([[ -f $UNITS/linux-lab-scrub.timer ]] && echo on || echo off); last: $(sudo btrfs scrub status / 2>/dev/null | grep -E 'Scrub (started|resumed)|no stats' | head -n 1 | tr -s ' ')" ;;
    esac
}
quiet_services() {
    local u
    case $1 in
    on)
        for u in $QUIET_UNITS; do sudo systemctl disable --now "$u" 2>/dev/null && echo "$u: disabled"; done
        ;;
    off)
        for u in $QUIET_UNITS; do sudo systemctl preset "$u" 2>/dev/null && echo "$u: $(systemctl is-enabled "$u" 2>/dev/null) (Fedora's preset)"; done
        ;;
    status)
        printf 'quiet services:'; for u in $QUIET_UNITS; do printf ' %s=%s' "${u%.service}" "$(systemctl is-enabled "$u" 2>/dev/null || echo none)"; done; echo
        ;;
    esac
}
quiet_net() {
    local a f st=$UHOME/.local/state/linux-lab
    case $1 in
    on)
        sudo mkdir -p "$(dirname "$NM_CONF")"
        printf '%s\n' '# Written by settings.sh quiet-net on; removed by quiet-net off and by uninstall.' '[connectivity]' 'enabled=false' |
            sudo tee "$NM_CONF" >/dev/null
        sudo systemctl try-reload-or-restart NetworkManager.service 2>/dev/null || true
        for a in $QUIET_AUTOSTART; do
            f=$UHOME/.config/autostart/$a
            [[ -e $f ]] && ! grep -q 'settings.sh quiet-net' "$f" && { echo "kept, yours: $f"; continue; }
            sudo -u "${SUDO_USER:-$(id -un)}" mkdir -p "$UHOME/.config/autostart"
            printf '%s\n' '[Desktop Entry]' '# Written by settings.sh quiet-net on; removed by quiet-net off.' 'Hidden=true' |
                sudo -u "${SUDO_USER:-$(id -un)}" tee "$f" >/dev/null
        done
        sudo pkill -u "${SUDO_USER:-$(id -un)}" -f 'geoclue-2.0/demos/agent|/DiscoverNotifier' 2>/dev/null || true
        if command -v abrt-auto-reporting >/dev/null; then
            sudo -u "${SUDO_USER:-$(id -un)}" mkdir -p "$st"
            [[ -f $st/abrt-auto-reporting.before ]] || abrt-auto-reporting 2>/dev/null | sudo -u "${SUDO_USER:-$(id -un)}" tee "$st/abrt-auto-reporting.before" >/dev/null
            sudo abrt-auto-reporting disabled >/dev/null
        fi
        quiet_net status
        ;;
    off)
        sudo rm -f "$NM_CONF"
        sudo systemctl try-reload-or-restart NetworkManager.service 2>/dev/null || true
        for a in $QUIET_AUTOSTART; do
            f=$UHOME/.config/autostart/$a
            if [[ -f $f ]] && grep -q 'settings.sh quiet-net' "$f"; then sudo rm -f "$f"; fi
        done
        if [[ -s $st/abrt-auto-reporting.before ]]; then
            sudo abrt-auto-reporting "$(tr -d '[:space:]' <"$st/abrt-auto-reporting.before")" >/dev/null || true
            sudo rm -f "$st/abrt-auto-reporting.before"
        fi
        quiet_net status
        ;;
    status)
        printf 'quiet net: connectivity check %s; hidden at login:' "$([[ -f $NM_CONF ]] && echo off || echo on)"
        for a in $QUIET_AUTOSTART; do grep -qs 'settings.sh quiet-net' "$UHOME/.config/autostart/$a" && printf ' %s' "${a%.desktop}"; done
        echo "; ABRT auto-reporting $(abrt-auto-reporting 2>/dev/null || echo -)"
        ;;
    esac
}
# Firefox reads /etc/firefox/policies/policies.json instead of the policies its package ships in
# distribution/ (EnterprisePoliciesParent.sys.mjs, JSONPoliciesProvider), so the file written
# here starts from the package's and adds ours. JSON has no comments: the "_written_by" key,
# which Firefox ignores (it reads only "policies"), marks the file as this script's.
FF_OURS='{"DisableTelemetry": true, "DisableFirefoxStudies": true, "DisablePocket": true,
 "FirefoxHome": {"SponsoredTopSites": false, "SponsoredStories": false},
 "FirefoxSuggest": {"SponsoredSuggestions": false, "ImproveSuggest": false},
 "GenerativeAI": {"Chatbot": false}}'
FF_MERGE_PY='
import json, sys
dist, ours = sys.argv[1], json.loads(sys.argv[2])
try:
    base = json.load(open(dist)).get("policies", {})
except FileNotFoundError:
    base = {}
for k, v in ours.items():
    base[k] = {**base[k], **v} if isinstance(v, dict) and isinstance(base.get(k), dict) else v
print(json.dumps({"_written_by": "linux-lab settings.sh firefox-quiet on; removed by firefox-quiet off and by uninstall",
                  "policies": base}, indent=2, sort_keys=True))
'
# noatime on the system disk's btrfs mounts (/ and /home): no metadata write for every file read, which on a
# copy-on-write filesystem also means less churn in its trees and snapshots. Access times are lost (the operator
# does not use them, 28 Oct). The fstab lines are edited in place; off takes the word out again. Both remount now.
noatime() {
    local f=/etc/fstab
    case $1 in
    on | off)
        [[ -f $f.settings-orig ]] || sudo cp -p "$f" "$f.settings-orig"
        sudo python3 -I - "$f" "$1" <<'PY'
import sys
path, mode = sys.argv[1], sys.argv[2]
out = []
for line in open(path).read().splitlines():
    w = line.split()
    if len(w) >= 4 and not line.lstrip().startswith("#") and w[2] == "btrfs" and w[1] in ("/", "/home"):
        opts = [o for o in w[3].split(",") if o not in ("noatime", "relatime", "atime")]
        if mode == "on":
            opts.append("noatime")
        w[3] = ",".join(opts) or "defaults"
        line = " ".join(w)
    out.append(line)
open(path, "w").write("\n".join(out) + "\n")
PY
        sudo systemctl daemon-reload
        local o; [[ $1 == on ]] && o=noatime || o=relatime
        sudo mount -o remount,$o / && sudo mount -o remount,$o /home
        echo "noatime: $1; / and /home now: $(findmnt -n -o OPTIONS / | tr ',' '\n' | grep -E 'atime' | tr '\n' ' ')/ $(findmnt -n -o OPTIONS /home | tr ',' '\n' | grep -E 'atime' | tr '\n' ' ')"
        ;;
    status) echo "noatime: $(grep -E '^[^#].*\sbtrfs\s.*noatime' "$f" >/dev/null && echo on || echo off) ($(findmnt -n -o OPTIONS / | tr ',' '\n' | grep atime))" ;;
    esac
}

firefox_quiet() {
    local d
    case $1 in
    on)
        if [[ -e $FF_POLICY ]] && ! grep -q '"_written_by": "linux-lab settings.sh firefox-quiet' "$FF_POLICY"; then
            echo "Firefox policy: kept, not ours: $FF_POLICY"
            return 0
        fi
        sudo mkdir -p "$(dirname "$FF_POLICY")"
        python3 -c "$FF_MERGE_PY" "$FF_DIST" "$FF_OURS" | sudo tee "$FF_POLICY" >/dev/null
        sudo chmod 0644 "$FF_POLICY"
        firefox_quiet status
        echo "    (Firefox applies it at its next start; about:policies lists it)"
        ;;
    off)
        if [[ -f $FF_POLICY ]] && grep -q '"_written_by": "linux-lab settings.sh firefox-quiet' "$FF_POLICY"; then
            sudo rm -f "$FF_POLICY"
            for d in "$(dirname "$FF_POLICY")" "$(dirname "$(dirname "$FF_POLICY")")"; do
                rpm -qf "$d" >/dev/null 2>&1 || sudo rmdir --ignore-fail-on-non-empty "$d" 2>/dev/null || true
            done
        fi
        firefox_quiet status
        ;;
    status)
        if [[ ! -e $FF_POLICY ]]; then
            echo "Firefox policy: off (Firefox uses ${FF_DIST} if it exists)"
        elif grep -q '"_written_by": "linux-lab settings.sh firefox-quiet' "$FF_POLICY"; then
            echo "Firefox policy: on, $FF_POLICY: $(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["policies"])))' "$FF_POLICY")"
        else
            echo "Firefox policy: someone else's, $FF_POLICY"
        fi
        ;;
    esac
}
flathub() {
    case $1 in
    on)
        sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        echo "flathub: on"
        ;;
    off)
        if flatpak list --system --app --columns=origin 2>/dev/null | grep -qx flathub; then die "apps from Flathub are installed; remove them first"; fi
        sudo flatpak remote-delete --system flathub 2>/dev/null || true
        echo "flathub: off"
        ;;
    status) echo "flathub: $(flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub && echo on || echo off)" ;;
    esac
}
kernel_pin() {
    case $1 in
    on)
        sudo mkdir -p "$(dirname "$PIN_CONF")"
        printf '%s\n' '# Written by settings.sh kernel-pin on; removed by kernel-pin off and by uninstall.' \
            '# A new kernel-16k package would become the default and point /boot/dtb at its own device' \
            '# trees; the Thunderbolt kernel (kernel/tbt-kernel.sh) needs its own. Kernels change by hand only.' \
            '[main]' 'excludepkgs=kernel-16k*' | sudo tee "$PIN_CONF" >/dev/null
        echo "kernel pin: on ($PIN_CONF); dnf leaves kernel-16k* alone"
        ;;
    off)
        sudo rm -f "$PIN_CONF"
        echo "kernel pin: off"
        ;;
    status)
        echo "kernel pin: $([[ -f $PIN_CONF ]] && echo "on ($PIN_CONF)" || echo off)"
        ;;
    esac
}

write_hook() {
    sudo mkdir -p "$(dirname "$HOOK")"
    sudo tee "$HOOK" >/dev/null <<EOF
#!/bin/bash
# Written by settings.sh sleep-hook on; removed by sleep-hook off and by uninstall.
# systemd-sleep hook: the PCIe tunnels of the enclosures do not survive a suspend, so the
# disks behind them are unmounted and their PCIe devices detached before sleep, and the
# buses rescanned and fstab mounted again after resume (the thunderbolt driver rebuilds
# the tunnels by itself). Set DRY=1 to print instead of act.
POOL=$POOL
ROOT=$ROOT
run() { if [[ -n \${DRY:-} ]]; then echo "would: \$*"; else "\$@"; fi; }
tunneled() { # PCI devices behind a tunneled controller (its name ends in 30000000.pcie), endpoints only
    local d
    for d in /sys/bus/pci/devices/*; do
        [[ \$(readlink -f "\$d") == *30000000.pcie/* ]] || continue
        [[ \${d##*/} == *:00:00.0 ]] && continue   # the root port stays
        echo "\$d"
    done
}
case \$1 in
pre)
    findmnt -n "\$POOL" >/dev/null && run umount "\$POOL"
    for m in \$(findmnt -rn -o TARGET | grep -E "^\$ROOT/(data|parity)/" | sort -r); do run umount "\$m"; done
    for d in \$(tunneled); do run sh -c "echo 1 > \$d/remove"; done
    ;;
post)
    run sh -c 'echo 1 > /sys/bus/pci/rescan'
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        udevadm settle 2>/dev/null || true
        [[ \$(ls /dev/disk/by-label/ 2>/dev/null | grep -c '^HD_') -ge 32 ]] && break
        sleep 3
    done
    run mount -a
    ;;
esac
exit 0
EOF
    sudo chmod 755 "$HOOK"
}

case ${1:-} in
install)
    spin=${2:-30}
    "$LAB/storage/tbt-disks.sh" authorize on
    "$LAB/storage/tbt-disks.sh" spindown "$spin"
    "$LAB/desktop/ux-fix.sh" on
    # The dirty limit first: the kernel keeps a disk's max_bytes as a share of the global
    # limit, so the USB cap set before it shrank from 256 to 29 MiB when the limit dropped.
    dirty_limit on
    usb_cap on
    indexer on
    smartd_rescan on
    kernel_pin on
    smartd_quiet on
    no_llmnr on
    scrub on
    quiet_services on
    flathub on
    quiet_net on
    firefox_quiet on
    noatime on
    if [[ -f /etc/snapraid.conf ]]; then "$LAB/storage/snapraid-setup.sh" timers on; else echo "SnapRAID timers: later, once /etc/snapraid.conf exists (snapraid-setup.sh install)"; fi
    echo "suspend hook: not installed (untested); settings.sh sleep-hook on when you can test a suspend"
    ;;
uninstall)
    "$LAB/storage/tbt-disks.sh" authorize off
    "$LAB/storage/tbt-disks.sh" spindown off
    "$LAB/desktop/ux-fix.sh" off
    usb_cap off
    indexer off
    smartd_rescan off
    kernel_pin off
    dirty_limit off
    smartd_quiet off
    no_llmnr off
    scrub off
    quiet_services off
    flathub off
    quiet_net off
    firefox_quiet off
    noatime off
    [[ -f /etc/snapraid.conf ]] && "$LAB/storage/snapraid-setup.sh" timers off
    sudo rm -f "$HOOK"
    echo "removed"
    ;;
status)
    "$LAB/storage/tbt-disks.sh" status 2>/dev/null | grep -E '^(authorize|spin-down) rule' || true
    "$LAB/desktop/ux-fix.sh" show
    [[ -f /etc/snapraid.conf ]] && "$LAB/storage/snapraid-setup.sh" timers status
    echo "suspend hook: $([[ -x $HOOK ]] && echo "on ($HOOK)" || echo off)"
    echo "USB dirty cap: $([[ -f $USB_RULE ]] && echo "on ($USB_RULE)" || echo off)"; usb_cap_now status 2>/dev/null | sed 's/^/    /' || true
    indexer status
    smartd_rescan status
    kernel_pin status
    dirty_limit status
    smartd_quiet status
    no_llmnr status
    scrub status
    quiet_services status
    flathub status
    quiet_net status
    firefox_quiet status
    noatime status
    ;;
indexer | smartd-rescan | kernel-pin | dirty-limit | smartd-quiet | no-llmnr | scrub | quiet-services | flathub | quiet-net | firefox-quiet | noatime)
    f=${1//-/_}
    case ${2:-} in on | off) "$f" "$2" ;; *) die "usage: $0 $1 on|off" ;; esac
    ;;
usb-cap)
    case ${2:-} in on | off) usb_cap "$2" ;; *) die "usage: $0 usb-cap on|off" ;; esac
    ;;
sleep-hook)
    case ${2:-} in
    on) write_hook; echo "suspend hook on: $HOOK. Test: systemctl suspend with the boxes on, then findmnt $POOL" ;;
    off) sudo rm -f "$HOOK"; echo "suspend hook off" ;;
    test) write_hook; echo "--- pre (dry)"; DRY=1 "$HOOK" pre; echo "--- post (dry)"; DRY=1 "$HOOK" post ;;
    *) die "usage: $0 sleep-hook on|off|test" ;;
    esac
    ;;
*)
    echo "usage: $0 {install [SPINDOWN_MIN] | uninstall | status | sleep-hook on|off|test | usb-cap | indexer | smartd-rescan | kernel-pin | dirty-limit | smartd-quiet | no-llmnr | scrub | quiet-services | flathub | quiet-net | firefox-quiet on|off}" >&2
    exit 2
    ;;
esac
