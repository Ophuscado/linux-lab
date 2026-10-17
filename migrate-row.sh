#!/usr/bin/env bash
# shellcheck disable=SC2024
# (the log file belongs to the user; sudo is for the command only)
# migrate-row.sh: move four rows of eight 18 TB disks from HFS+ into one XFS pool made of
# the same bays, disk by disk, until each row's parity disk (24, 00, 08, 16) is empty.
#
# The plan, in plain words. A row is eight bays, one enclosure:
#
#   A  24 25 26 27 28 29 30 31   parity 24
#   B  00 01 02 03 04 05 06 07   parity 00
#   C  08 09 10 11 12 13 14 15   parity 08
#   D  16 17 18 19 20 21 22 23   parity 16
#
# The pool is one mergerfs union of every bay this script has formatted to XFS, in any row,
# the parity bays excepted, mounted at ~/migrate/pool. Each new file goes to a branch drawn
# at random, weighted by free space, so the data spreads over every writable disk, parallel
# copies write to different disks, and no single disk has to fit a whole source. Every disk still on HFS+ with more than 10 GB on it is a source (an
# emptier one holds only HFS+ metadata and is just formatted when needed). One worker per
# row is one read stream per enclosure; each round takes the SMALLEST remaining source of
# its row (the parity disk last, since emptying it frees no bay; a deferred disk after
# that), copies it into the pool, checks the copy, and only then may the source be
# formatted and added to the pool as a fresh branch. Small disks go first, so bays join the
# pool early. When the pool lacks room, a worker formats an emptied bay of its own row,
# else of any row. Workers reserve their source's size in the pool, so four copies at once
# cannot run it dry.
#
# Workers: "start B" runs one worker for row B; "start B 2" two (same pool, two sources).
#
# What one round does, and what stops it:
#   1. If the pool lacks room for the source, a bay is formatted: one GPT partition, XFS,
#      label HD_nn, then added to the pool. The one destructive command. It happens on its
#      own only for a disk this script emptied by a verified copy or found under 10 GB; any
#      other disk needs you to type "erase nn" at the prompt, after seeing what it holds.
#      Seven bays hold a row's data; when all eight disks hold data, the old parity disk
#      (last bay) is the one that asks. "migrate-row.sh erase 07 15 23 31" records in
#      advance that a disk's content is not needed (the old parity disks, migrated already):
#      it is then never copied, is the first bay formatted, and nothing asks.
#   2. The source is mounted read-only and rsync copies everything into the pool with
#      owners, times, permissions, hard links and extended attributes (resource forks do
#      not exist on Linux and are not copied; neither are the Apple attributes, Finder
#      info, quarantine and Spotlight metadata, which the driver cannot read; nor the
#      volume's own bookkeeping: .journal, .fseventsd, .Spotlight-V100, .Trashes, .DS_Store
#      and the like, which every HFS+ volume has and which are not data). A file that
#      already exists in the pool under the same path is never overwritten
#      (--ignore-existing); verification then reports it.
#   3. Verification: every file of the source is looked up in the pool and compared by size
#      and time (VERIFY=full reads both back and compares checksums; twice the time). Any
#      difference stops the worker; the source is untouched.
#   4. The source is marked "copied, verified"; it may now be formatted and join the pool.
# Parent folders with the same name on several sources merge into one folder in the pool,
# which is what a library spread over disks looks like afterwards.
# A disk on a flaky link ("defer 28") is copied after everything else in its row.
# The disks are trusted until one fails: when a pool disk logs a failed write, the files written
# to it in the 30 minutes before go aside on it (copied again later), and every worker stops;
# "start" trusts the disks again, after a replug, a reboot or nothing.
# A worker logs to ~/migrate/<row>.log; state lives in ~/migrate/state/. A stopped or
# crashed worker is restarted with the same command and continues. Workers run as root
# inside root's tmux server (one password at "start"), so a copy that takes a day is never
# stopped by a sudo prompt in a pane nobody watches. The pool mount is
# recreated from the formatted bays whenever a worker starts.
#
#   migrate-row.sh plan A           what the row holds and what the first round would do
#   migrate-row.sh start A [N]      run N workers (default 1) in root's tmux sessions mig-A-1..N
#   migrate-row.sh run A            one worker in this terminal
#   migrate-row.sh status           every row: disks copied, workers, pool, mounts
#   migrate-row.sh attach A [N]     watch a worker (Ctrl-b d to leave it running)
#   migrate-row.sh pool             mount the pool without copying (after a reboot)
#   migrate-row.sh stats [SECONDS]  the pool and each branch: fill, and MB/s read and
#                                   written per disk over SECONDS (default 5)
#   migrate-row.sh defer 28 ...     copy these disks last in their row (unstable link)
#   migrate-row.sh heal             try a write on every pool branch; drop (and mark bad) those
#                                   that fail. Workers do this at each copy and after a failed
#                                   pass, so a dead disk costs a rerun, not the worker.
#   migrate-row.sh rescan [NN ...]  look again for disks the system lost (default: all of them),
#                                   e.g. after a reseat, without a reboot
#   migrate-row.sh bad 15 ...       take these bays out of the pool by hand (they stay out after
#                                   a restart); good 15 ... puts them back. Files they held are
#                                   copied again from the sources, which are still there.
#   migrate-row.sh aside 15 "2026-10-16 21:33" ["2026-10-16 22:10"]
#                                   what a worker does when a pool disk fails a write, by hand (for
#                                   one no worker saw): files changed on hd-15 since then (and not
#                                   after the second time) go aside on it, copied again by the next
#                                   pass; run it before 'good 15'
#   migrate-row.sh recheck NN ...   after a disk or box fault during copies: files of these
#                                   sources that exist in the pool are compared, and a copy
#                                   that differs, or that exists on two branches, is moved
#                                   aside on its disk (.migrate-aside/), so the next pass
#                                   rewrites it instead of skipping it. Nothing deleted.
#                                   Whole sources: by checksum, takes a day. With
#                                   MIG_RECHECK_SINCE="YYYY-MM-DD HH:MM" (and MIG_RECHECK_UNTIL)
#                                   only the pool files written in that window, the fault's
#                                   last minutes, by size (VERIFY=quick, the default) or by
#                                   bytes (VERIFY=full); rows side by side. MIG_RECHECK_DUPS=0
#                                   skips the two-branch pass (it walks every branch).
#   migrate-row.sh finish           when every worker is done: checks all 32 disks are XFS,
#                                   unmounts the migration pool and mounts; next is
#                                   snapraid-setup.sh install, mount, first
#   migrate-row.sh add 23 ...       format these bays now and add them to the pool (only
#                                   disks already copied, marked "erase" or found empty;
#                                   otherwise a worker does it when the pool needs room)
#   migrate-row.sh mergerfs        build and install mergerfs 2.42.0 (once; Fedora has no package)
#   migrate-row.sh readtest ROW [start | check [SECONDS] | stop]
#                                   link test of one box, reads only: start reads every present
#                                   disk of the row from its beginning at full speed, all at once,
#                                   in root's tmux session test-ROW, until stop (a new start reads
#                                   from the beginning again). check (the default) shows each
#                                   disk's read rate now and since the start, and the link and I/O
#                                   errors since the start by disk; with SECONDS, again every
#                                   SECONDS until Ctrl-C
#   migrate-row.sh pause ROW... | all   stop a row's worker where it is; resume ROW... | all
#                                   goes on (33: the copy of disk 33)
#   migrate-row.sh rest 15 | off    the rows take turns to rest, one at a time, 15 minutes each:
#                                   every box rests 15 minutes an hour (cooler, 25 % slower)
#   migrate-row.sh policy [NAME]    where the pool puts new files: pfrd (default; random,
#                                   weighted by free space, parallel copies spread over the disks)
#                                   or mfs (always the emptiest disk: a new or lagging disk catches
#                                   up, but every copy writes to that one disk at a time). Applied
#                                   to the mounted pool at once and kept for later mounts; without
#                                   NAME, shows the live and the kept one
#   migrate-row.sh extra [PART]     copy disk 33, the external USB HFS+ disk (no label; found as the
#                                   one HFS+ partition over 10 TB on USB, or PART), into the pool in
#                                   root's tmux session mig-33, log ~/migrate/33.log. Without
#                                   extended attributes (git clones and plain data). Run it again
#                                   after a reboot: what is already in the pool is skipped
#   migrate-row.sh erase 07 15 ...  mark disks whose content is not needed: formatted
#                                   without a copy and without asking
#
# Needs ~/disk-plan.csv from disk-inventory.sh with every disk named, and the packages
# xfsprogs rsync tmux parted attr (installed on the first run) and mergerfs ("mergerfs" command).
#
# Test hooks: MIG_PLAN, MIG_HOME, MIG_SRC_FS (filesystem type of the sources, hfsplus),
# MIG_EMPTY_LIMIT (bytes), MIG_MINFREE (mergerfs minfreespace), MIG_MERGERFS (binary),
# MIG_WAIT (seconds between looks at a full pool), MIG_PROBE (seconds a branch gets to take a
# write), MIG_SYS (a sysfs root) and MIG_DMESG (a file read instead of the kernel log).

set -euo pipefail

PLAN=${MIG_PLAN:-$HOME/disk-plan.csv}
MIG=${MIG_HOME:-$HOME/migrate}
SRC_FS=${MIG_SRC_FS:-hfsplus}
VERIFY=${VERIFY:-quick}
EMPTY_LIMIT=${MIG_EMPTY_LIMIT:-10000000000} # bytes; under 10 GB is HFS+ metadata, not data
MINFREE=${MIG_MINFREE:-4G} # mergerfs stops placing new files on a branch below this
# Where a new file goes: pfrd picks a branch at random, weighted by free space, so parallel
# streams land on different disks (mfs would send them all to the emptiest one at a time).
# 'policy' changes it and keeps the choice in $MIG/state/create for later mounts and workers.
CREATE=${MIG_CREATE:-$(cat "$MIG/state/create" 2>/dev/null || echo pfrd)}
MERGERFS=${MIG_MERGERFS:-mergerfs}
# HFS+ keeps its own bookkeeping as files in the volume root; each disk has its own, they
# collide in the pool and are no data. Never copied, never reported by verify.
VOLUME_FILES=(/.journal /.journal_info_block /.fseventsd /.Spotlight-V100 /.Trashes /.TemporaryItems
    /.DocumentRevisions-V100 /.hotfiles.btree '/.HFS+ Private Directory Data*' /.DS_Store)
volume_excludes() { local f; for f in "${VOLUME_FILES[@]}"; do printf -- "--exclude=%s\n" "$f"; done; }
POOL=$MIG/pool
WAIT=${MIG_WAIT:-300}
MERGERFS_TAG=2.42.0 # built from source: Fedora 44 has no mergerfs package

declare -A ROW=(
    [A]="24 25 26 27 28 29 30 31"
    [B]="00 01 02 03 04 05 06 07"
    [C]="08 09 10 11 12 13 14 15"
    [D]="16 17 18 19 20 21 22 23"
)
declare -A PARITY=([A]=24 [B]=00 [C]=08 [D]=16)

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2; }

# ---- disks ------------------------------------------------------------------------------

# $1 name (two digits): the disk's /dev/disk/by-id path from the plan file.
BYID=${MIG_BYID:-/dev/disk/by-id}
# Disk $1's /dev/disk/by-id link now: the plan's own (disk-inventory.sh took the ata- name), else
# one that ends in the disk's serial. Behind a SAS card udev names a SATA disk scsi-SATA_<model>_<serial>
# (and wwn-), and its ata- name does not exist; a disk moved between boxes keeps its serial. Empty
# when the system does not have the disk.
link_of() {
    local byid serial l
    IFS=, read -r byid serial < <(awk -F, -v n="$1" '$14 == n { print $4 "," $5; exit }' "$PLAN") || return 0
    if [[ -n $byid && -e $byid ]]; then echo "$byid"; return 0; fi
    [[ -n $serial ]] || return 0
    for l in "$BYID"/*_"$serial"; do
        [[ -e $l ]] && { echo "$l"; return 0; }
    done
    return 0
}
# The plan's names, one per line.
plan_names() { tail -n +2 "$PLAN" | cut -d, -f14; }

disk_of() {
    local d
    d=$(awk -F, -v n="$1" '$14 == n { print $4 }' "$PLAN")
    [[ -n $d ]] || die "disk $1 is not in $PLAN"
    [[ $(wc -l <<<"$d") == 1 ]] || die "disk $1 appears more than once in $PLAN; run disk-inventory.sh again"
    d=$(link_of "$1")
    [[ -n $d && -b $d ]] || die "disk $1 ($(awk -F, -v n="$1" '$14 == n { print $4 }' "$PLAN"), serial $(awk -F, -v n="$1" '$14 == n { print $5 }' "$PLAN")) is not present"
    echo "$d"
}

# The partition that holds the volume: the last one.
part_of() {
    local p
    p=$(lsblk -lnpo NAME,TYPE "$(readlink -f "$1")" | awk '$2 == "part" {print $1}' | tail -n 1)
    [[ -n $p ]] || die "no partition on $1"
    echo "$p"
}

# blkid reads the device itself, so a fresh filesystem is seen before udev catches up.
fstype_of() { sudo blkid -p -s TYPE -o value "$1" 2>/dev/null || true; }
label_of() { sudo blkid -p -s LABEL -o value "$1" 2>/dev/null || true; }

# Mount $2 (partition) at $3, options $4; nothing if already there.
mount_at() {
    sudo mkdir -p "$3"
    findmnt -n "$3" >/dev/null && return 0
    sudo mount -o "$4" "$2" "$3"
}

# Bytes used / available on a mounted filesystem.
# df looks at every mount to find the one of its argument and exits 1, with an error, if one of
# them (a dead branch) answers EIO; the number it prints for the argument is still right.
used_at() { { df -B1 --output=used "$1" 2>/dev/null || true; } | tail -n 1 | tr -d ' '; }
avail_at() { { df -B1 --output=avail "$1" 2>/dev/null || true; } | tail -n 1 | tr -d ' '; }

SYS=${MIG_SYS:-/sys}
kernel_log() { if [[ -n ${MIG_DMESG:-} ]]; then cat "$MIG_DMESG"; else sudo dmesg -T 2>/dev/null || true; fi; }
# A line of ours in the kernel log, so that a report can start from it.
kernel_mark() { if [[ -n ${MIG_DMESG:-} ]]; then echo "[$(date)] $1" >>"$MIG_DMESG"; else echo "$1" | sudo tee /dev/kmsg >/dev/null; fi; }

# ataN -> the disk's name in the plan: the disk on the port now, so a disk moved to another bay
# keeps its name; for a port without a disk, the plan's disk for that domain and port, counted
# as disk-inventory.sh does (the port's SCSI host, from the controller's first). A port that has
# lost its disk still resolves: the port stays in sysfs.
ata_name() {
    local p dom host base h blk byid name
    p=$(readlink -f "$SYS/class/ata_port/$1" 2>/dev/null) || { echo '?'; return; }
    for blk in "${p%/ata_port/*}"/host*/target*/*/block/*; do
        [[ -e $blk ]] || continue
        while read -r name; do
            byid=$(link_of "$name")
            [[ -n $byid && $(readlink -f "$byid") == */"${blk##*/}" ]] && { echo "$name"; return; }
        done < <(plan_names)
    done
    dom=$(grep -oE '/[0-9a-f]{4}:03:00\.0/' <<<"$p" | tr -d / | cut -d: -f1 || true)
    host=$(ls -d "${p%/ata_port/*}"/host* 2>/dev/null | head -n 1 | grep -oE '[0-9]+$' || true)
    [[ -n $dom && -n $host ]] || { echo '?'; return; }
    base=$(for h in "$SYS"/class/scsi_host/host*; do
        [[ $(readlink -f "$h") == *"/$dom:03:00.0/"* ]] && echo "${h##*host}"; done | sort -n | head -n 1)
    # No disk on the port now: the plan's disk for it, unless that one sits elsewhere now (moved);
    # then the box's disks the system lacks are the candidates.
    name=$(awk -F, -v d="$dom" -v p="$((host - base))" '$1 == d && $2 == p { print $14 }' "$PLAN") || true
    if [[ -n ${name:-} && -z $(link_of "$name") ]]; then echo "$name? (no disk on the port now; the plan's disk for it)"; return; fi
    name=$(awk -F, -v d="$dom" '$1 == d { print $14 }' "$PLAN" | while read -r name; do [[ -n $(link_of "$name") ]] || echo "$name"; done | tr '\n' ' ')
    echo "?(domain $dom port $((host - base)), no disk now; missing from this box: ${name:-none})"
}

# The SCSI hosts a rescan asks for disk $1. A scan resets the port, so ports that hold a disk are
# left alone: the port that has the disk now, when the system still lists it (a disabled port
# keeps the /dev name); else every port of its box (the domain in the plan) without a disk, since
# the disk may have moved bays; else, for a disk moved behind a SAS card, that card's hosts.
hosts_of() {
    local byid dev p dom h
    grep -q ",$1\$" "$PLAN" || return 1
    byid=$(link_of "$1")
    if [[ -n $byid ]]; then
        dev=$(readlink -f "$byid")
        h=$(readlink -f "$SYS/block/${dev##*/}" 2>/dev/null | grep -oE '/host[0-9]+/' | head -n 1 | tr -d /) || true
        [[ -n $h ]] && { echo "$h"; return 0; }
    fi
    dom=$(awk -F, -v n="$1" '$14 == n { print $1 }' "$PLAN")
    [[ -n $dom ]] || return 1
    p=$(for h in "$SYS"/class/scsi_host/host*; do
        p=$(readlink -f "$h")
        [[ $p == *"/$dom:03:00.0/"* ]] || continue
        compgen -G "${p%/scsi_host/*}/target*/*/block/*" >/dev/null && continue
        echo "${h##*/}"
    done | sort -V)
    [[ -n $p ]] && { echo "$p"; return 0; }
    # Behind a SAS card a disk has no port of its own: the card's host is scanned, which adds what
    # is new and leaves the disks it has alone.
    for h in "$SYS"/class/scsi_host/host*; do
        [[ $(cat "$h/proc_name" 2>/dev/null) == mpt3sas ]] && echo "${h##*/}"
    done | sort -V | grep .
}

# Does disk $1 answer a read of its first block within 30 s? A port the kernel has disabled keeps
# the /dev name, so being there is not enough. In the background: a hung read is abandoned.
disk_answers() {
    local d pid i
    d=$(link_of "$1")
    [[ -n $d ]] || return 1
    [[ -b $d ]] || return 0 # tests: a plain file stands for the disk
    ( sudo dd if="$d" of=/dev/null bs=4096 count=1 iflag=direct status=none ) 2>/dev/null &
    pid=$!
    for ((i = 0; i < 30; i++)); do
        kill -0 "$pid" 2>/dev/null || { wait "$pid"; return; }
        sleep 1
    done
    return 1
}

# Disks of the plan the system does not have now.
missing_disks() {
    local name
    while read -r name; do [[ -n $(link_of "$name") ]] || echo "$name"; done < <(plan_names)
}

# The links: disks of the plan the system no longer has, and SATA trouble since boot per disk.
link_report() {
    local dom port dev byid name nn miss="" cnt ata last n=0
    while IFS=, read -r dom port _ _ _ _ _ _ _ _ _ _ _ name; do
        [[ -n $(link_of "$name") ]] || miss+="$name (domain $dom, port $port in the plan) "
    done < <(tail -n +2 "$PLAN")
    echo "    missing from the system: ${miss:-none}${miss:+ ('rescan' looks for them again)}"
    # A port whose disk failed to answer through all of libata's retries is disabled: the disk may
    # still show in /dev, but every command to it fails at once. "configured for" after it means
    # the port came back.
    while IFS=$'\t' read -r ata last; do
        [[ -e $SYS/class/ata_port/$ata ]] || continue # the port itself went away (the box re-enumerated)
        echo "    $(ata_name "$ata") ($ata): disabled by the kernel since $last; nothing reaches it until 'rescan' or a reboot"; n=$((n + 1))
    done < <(kernel_log | grep -E '\] ata[0-9]+\.[0-9]+: (disable device|configured for)' |
        sed -E 's/^\[([^]]*)\] (ata[0-9]+)\.[0-9]+: (disable|configured).*/\2\t\3\t\1/' |
        awk -F'\t' '{ st[$1] = $2; t[$1] = $3 } END { for (a in st) if (st[a] == "disable") print a "\t" t[a] }' | sort -V)
    while IFS=$'\t' read -r cnt ata last; do
        echo "    $(ata_name "$ata") ($ata): $cnt link errors since boot, last $last"; n=$((n + 1))
    # "link down (SStatus 0" alone is an empty bay at probe time; a disk that drops says more.
    done < <(kernel_log | grep -E '\] ata[0-9]+(\.[0-9]+)?: .*(BadCRC|Handshk|timeout|failed to IDENTIFY|exception Emask|hard resetting link|link down|limiting SATA link speed)' |
        grep -v 'SATA link down (SStatus 0 ' |
        sed -E 's/^\[([^]]*)\] (ata[0-9]+)[.:].*/\2\t\1/' |
        awk -F'\t' '{ n[$1]++; last[$1] = $2 } END { for (a in n) print n[a] "\t" a "\t" last[a] }' | sort -rn | head -n 12)
    while IFS=$'\t' read -r cnt dev last; do
        echo "    $(name_of_dev "$dev"): $cnt I/O errors since boot, last $last"; n=$((n + 1))
    done < <(kernel_log | grep -E '\] I/O error, dev sd[a-z]+' | sed -E 's/^\[([^]]*)\] I\/O error, dev (sd[a-z]+).*/\2\t\1/' |
        awk -F'\t' '{ n[$1]++; last[$1] = $2 } END { for (a in n) print n[a] "\t" a "\t" last[a] }' | sort -rn | head -n 12)
    # Commands the disk failed, also those retried with success: the SCSI layer logs them for any
    # disk, including one behind a SAS card, which has no ataN port and no libata lines.
    while IFS=$'\t' read -r cnt dev last; do
        echo "    $(name_of_dev "$dev"): $cnt failed commands since boot, last $last"; n=$((n + 1))
    done < <(kernel_log | grep -E '\] sd [0-9:]+: \[[a-z][a-z0-9]*\] tag#[0-9]+ FAILED Result' |
        sed -E 's/^\[([^]]*)\] sd [0-9:]+: \[([a-z][a-z0-9]*)\].*/\2\t\1/' |
        awk -F'\t' '{ n[$1]++; last[$1] = $2 } END { for (a in n) print n[a] "\t" a "\t" last[a] }' | sort -rn | head -n 12)
    ((n > 0)) || echo "    no SATA link, I/O or command errors since boot"
}

# sdX -> "NN (sdX)", the plan's name of the disk that has that /dev name now.
name_of_dev() {
    local nn byid
    while read -r nn; do
        byid=$(link_of "$nn")
        [[ -n $byid && $(readlink -f "$byid") == "/dev/$1" ]] && { echo "$nn ($1)"; return; }
    done < <(plan_names)
    echo "$1 (no disk has that name now)"
}

# $1 name: "src USED" (still on HFS+), "xfs USED AVAIL" (formatted by us), or "other TYPE".
# Mounts the volume read-only for the figures and unmounts it again.
disk_state() {
    local nn=$1 dev part fs m
    dev=$(disk_of "$nn") || exit 1
    part=$(part_of "$dev") || exit 1
    fs=$(fstype_of "$part")
    m=$MIG/mnt/peek-$nn
    case $fs in
    "$SRC_FS")
        mount_at "$nn" "$part" "$m" ro
        echo "src $(used_at "$m")"
        sudo umount "$m"
        ;;
    xfs)
        [[ $(label_of "$part") == "HD_$nn" ]] || { echo "other xfs-not-ours"; return; }
        # A pool branch is already mounted read-write; read the figures there.
        if findmnt -n -S "$part" >/dev/null; then
            m=$(findmnt -n -S "$part" -o TARGET | head -n 1)
            echo "xfs $(used_at "$m") $(avail_at "$m")"
        else
            mount_at "$nn" "$part" "$m" ro
            echo "xfs $(used_at "$m") $(avail_at "$m")"
            sudo umount "$m"
        fi
        ;;
    *) echo "other ${fs:-none}" ;;
    esac
}

# ---- the steps --------------------------------------------------------------------------

# $1 target name. The destructive step.
format_target() {
    local mm=$1 dev part answer st
    dev=$(disk_of "$mm") || exit 1
    st=$(disk_state "$mm")
    if [[ $st == xfs* ]]; then
        log "$mm: already XFS"
        return 0
    fi
    if [[ ! -f $MIG/state/$mm.copied ]]; then
        echo
        echo "About to ERASE disk $mm: $dev"
        echo "  $(readlink -f "$dev"), $(lsblk -dno MODEL,SIZE "$dev" | tr -s ' ')"
        echo "  holds ${st#* } bytes on $(fstype_of "$(part_of "$dev")") '$(label_of "$(part_of "$dev")")'"
        echo "  this script has NOT copied it anywhere."
        read -r -p "Type 'erase $mm' to erase it: " answer </dev/tty
        [[ $answer == "erase $mm" ]] || die "not confirmed; nothing changed"
    fi
    log "$mm: formatting $dev as XFS, label HD_$mm"
    # The read-only udev rule may have flagged the disk; the flags are cleared first.
    sudo blockdev --setrw "$dev"
    for p in $(lsblk -lnpo NAME,TYPE "$(readlink -f "$dev")" | awk '$2 == "part" {print $1}'); do
        sudo umount "$p" 2>/dev/null || true
        sudo blockdev --setrw "$p" 2>/dev/null || true
    done
    sudo wipefs -a "$dev" >>"$LOG" 2>&1
    sudo parted -s "$dev" mklabel gpt mkpart data xfs 1MiB 100% >>"$LOG" 2>&1
    sudo partprobe "$dev"
    # The new partition node can take a moment to appear.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        part=$(lsblk -lnpo NAME,TYPE "$(readlink -f "$dev")" | awk '$2 == "part" {print $1}' | tail -n 1)
        [[ -n $part && -b $part ]] && break
        sleep 1
    done
    [[ -n $part && -b $part ]] || die "$mm: no partition appeared on $dev after formatting"
    sudo blockdev --setrw "$part"
    # A 256 MiB log instead of the 2 GiB default: two disks are within 2 GB of full.
    sudo mkfs.xfs -q -f -L "HD_$mm" -l size=256m "$part" >>"$LOG" 2>&1 || die "$mm: mkfs.xfs failed; see $LOG"
    rm -f "$MIG/state/$mm.copied"
    log "$mm: formatted"
}

# ---- the pool ---------------------------------------------------------------------------

# Mount bay $1 read-write at its place under the pool's branches.
mount_branch() {
    local mm=$1 d
    d=$(part_of "$(disk_of "$mm")") || exit 1
    [[ $(fstype_of "$d") == xfs && $(label_of "$d") == "HD_$mm" ]] || die "$mm is not the XFS disk HD_$mm"
    # A branch directory with nothing mounted on it is a plain folder of the system disk, and a pool
    # that still lists it writes there. Mounting the bay over files like that would hide them.
    if ! findmnt -n "$MIG/mnt/hd-$mm" >/dev/null && [[ -n $(sudo ls -A "$MIG/mnt/hd-$mm" 2>/dev/null) ]]; then
        die "$MIG/mnt/hd-$mm holds files while nothing is mounted there (the pool wrote to the system disk while bay $mm was out). Move them into the pool first: sudo rsync -a --remove-source-files $MIG/mnt/hd-$mm/ $POOL/"
    fi
    sudo blockdev --setrw "$d"
    mount_at "$mm" "$d" "$MIG/mnt/hd-$mm" rw,noatime
}

# Bays of rows $@ (default all) that are XFS and not a parity disk, in bay order.
branches_of() {
    local row mm rows=${*:-A B C D}
    local part
    for row in $rows; do
        for mm in ${ROW[$row]}; do
            [[ $mm == "${PARITY[$row]}" ]] && continue
            [[ -e $MIG/state/$mm.bad ]] && continue # found dead: out of the pool until 'good'
            # Type and label only: no mount, so 32 cold disks do not each spin up for a look. A disk
            # the system has lost is no branch (and no reason to stop: start and every worker ask).
            part=$(part_of "$(disk_of "$mm" 2>/dev/null)" 2>/dev/null) || continue
            [[ $(fstype_of "$part") == xfs && $(label_of "$part") == "HD_$mm" ]] && echo "$mm"
        done
    done
}

# Mount the pool over its current branches. A branch that fills up mid-file hands the file on.
pool_mount() {
    local mm list=""
    sudo mkdir -p "$POOL"
    for mm in $(branches_of); do
        mount_branch "$mm"
        list+="${list:+:}$MIG/mnt/hd-$mm"
    done
    [[ -n $list ]] || return 1
    if findmnt -n "$POOL" >/dev/null; then
        # Already mounted: apply the placement policy and add any formatted bay it lacks.
        sudo setfattr -n user.mergerfs.category.create -v "$CREATE" "$POOL/.mergerfs"
        for mm in $(branches_of); do
            sudo getfattr -n user.mergerfs.branches --only-values "$POOL/.mergerfs" 2>/dev/null | tr ':' '\n' | grep -qx "$MIG/mnt/hd-$mm=RW" ||
                sudo setfattr -n user.mergerfs.branches -v "+>$MIG/mnt/hd-$mm" "$POOL/.mergerfs"
        done
        return 0
    fi
    # allow_other: a FUSE mount is private to the mounting user (root here) without it.
    sudo "$MERGERFS" -o "allow_other,category.create=$CREATE,moveonenospc=true,minfreespace=$MINFREE,cache.files=off,dropcacheonclose=true,fsname=pool" \
        "$list" "$POOL"
}

pool_branches() { sudo getfattr -n user.mergerfs.branches --only-values "$POOL/.mergerfs" 2>/dev/null | sed 's|=RW||g; s|[^:]*/hd-||g; s|:| |g'; }

# A bay found dead (state/NN.bad) stays out of the pool, also after a restart, until 'good NN'.
mark_bad() {
    touch "$MIG/state/$1.bad"
    sudo setfattr -n user.mergerfs.branches -v "-$MIG/mnt/hd-$1" "$POOL/.mergerfs" 2>/dev/null || true
    # Detached (lazily: a dead disk hangs a plain umount), so that df and mkdir stop stumbling on it.
    sudo umount -l "$MIG/mnt/hd-$1" 2>/dev/null || true
    uncopy "$1" >/dev/null
}

# uncopy NN [SINCE]: the sources verified (since SINCE, "YYYY-MM-DD HH:MM:SS") while hd-NN was a pool
# branch may have copies on it that the pool no longer shows. Not formatted yet: each is a source
# again, and the next pass copies what the pool lacks. Formatted already: some of its files may
# exist only on hd-NN, which must stay as it is. Prints the formatted ones.
uncopy() {
    local src part
    while read -r src; do
        part=$(part_of "$(disk_of "$src" 2>/dev/null)" 2>/dev/null) || part=""
        if [[ -n $part && $(fstype_of "$part") != "$SRC_FS" ]]; then
            log "WARN $src was formatted after a verify with hd-$1 as a pool branch: files of $src may exist only on hd-$1. Keep hd-$1 as it is ('good $1' if it is out); never format it"
            echo "$src"; continue
        fi
        [[ ! -f $MIG/state/$src.copied ]] || mv "$MIG/state/$src.copied" "$MIG/state/$src.copied-before-$1-out"
        echo "$src -> pool  undone $(date '+%F %T'): hd-$1 went out of the pool or lost writes" >>"$MIG/state/placement.txt"
        if [[ -z $part ]]; then
            log "WARN $src was verified while hd-$1 was a pool branch and is not found now: it counts as not copied; once back, it is copied and verified anew"
        else
            log "WARN $src was verified while hd-$1 was a pool branch: it is a source again, copied and verified anew before it may be formatted"
        fi
    done < <(awk -v b="$1" -v since="${2:-0}" '
        / -> pool / {
            if ($4 == "undone") { ok[$1] = 0; next }
            hit = 0
            for (i = 1; i <= NF; i++) if ($i == "then:") for (j = i + 1; j <= NF; j++) if ($j == b) hit = 1
            ok[$1] = hit && ($6 " " $7) >= since
        }
        END { for (s in ok) if (ok[s]) print s }' "$MIG/state/placement.txt" 2>/dev/null | sort)
}

# ---- pauses -------------------------------------------------------------------------------------
# A row's processes: everything under its tmux sessions (mig-A-1..., or mig-33 for disk 33),
# parents before children. Not the pane's own shell: tmux continues a pane process that stops. And
# sudo watches the command it runs (use_pty) and mirrors a stop of it onto itself, so a pause
# stops parents first and a resume continues children first: the command runs again before sudo
# can look at it, and sudo never sees it stopped.
row_pids() {
    local ss pp
    for ss in $(sudo tmux ls -F '#S' 2>/dev/null | grep -E "^mig-$1(-[0-9]+)?\$" || true); do
        pp=$(sudo tmux list-panes -t "$ss" -F '#{pane_pid}' 2>/dev/null) || continue
        ps -eo pid=,ppid= | awk -v root="$pp" '
            { kids[$2] = kids[$2] " " $1 }
            END { q[1] = root; h = 1; t = 1
                  while (h <= t) { p = q[h++]; if (p != root) print p; m = split(kids[p], c, " "); for (i = 1; i <= m; i++) q[++t] = c[i] } }'
    done
}
pause_row() {
    local pids
    pids=$(row_pids "$1")
    [[ -n $pids ]] || { echo "row $1: no worker runs"; return 0; }
    sudo kill -STOP $pids 2>/dev/null || true
    date '+%F %T' >"$MIG/state/paused-$1"
    log "row $1 paused: $(wc -l <<<"$pids") processes stopped"
}
resume_row() {
    local pids
    pids=$(row_pids "$1" | tac)
    rm -f "$MIG/state/paused-$1"
    [[ -n $pids ]] || return 0
    sudo kill -CONT $pids 2>/dev/null || true
    log "row $1 resumed"
}

# ---- failed writes -----------------------------------------------------------------------------
# The disks are trusted until one fails a write: the kernel logs "I/O error, dev sdX, ... (WRITE)".
# rsync has moved on by then (it does not fsync), and the copy keeps the size it was given, so
# neither a check by size nor one by checksum through the page cache sees the loss. So when a pool
# branch's disk logs one, a worker (it looks every MIG_WATCH seconds while it copies, and before a
# verify):
#   - moves aside on that disk every file changed there since MIG_WRITE_MARGIN minutes (default 30)
#     before the error, into .migrate-aside/write-error-<time>/ (nothing deleted); the next pass
#     copies them again;
#   - makes a source verified since then a source again (uncopy);
#   - stops every worker and the copy of disk 33 ($MIG/state/stop says why).
# 'start' (or 'run') trusts the disks again, after a replug, a reboot or nothing: each log line is
# handled once ($MIG/state/write-errors.seen). A source formatted since then keeps its copies where
# they are; the stop then says so and nothing is moved.
WRITE_MARGIN=${MIG_WRITE_MARGIN:-30}
# The raw kernel log (seconds since boot): its lines do not change between two reads.
kernel_log_raw() { if [[ -n ${MIG_DMESG:-} ]]; then cat "$MIG_DMESG"; else sudo dmesg 2>/dev/null || true; fi; }
# A kernel log time stamp ("12345.678901" since boot, or a date) as "YYYY-MM-DD HH:MM:SS".
stamp_time() {
    if [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        date -d "@$(($(date +%s) - $(cut -d. -f1 /proc/uptime) + ${1%.*}))" '+%F %T'
    else
        date -d "$1" '+%F %T'
    fi
}
# start and run: the operator goes on, so the disks are trusted again.
trust_again() { [[ ! -f $MIG/state/stop ]] || { log "the stop is lifted, the disks are trusted again; it said: $(cat "$MIG/state/stop")"; rm -f "$MIG/state/stop"; }; }
stopped() { [[ ! -f $MIG/state/stop ]] || die "stopped: $(cat "$MIG/state/stop") 'start' trusts the disks again."; }
check_writes() {
    local seen=$MIG/state/write-errors.seen lock=$MIG/state/lock-writes new line dev br part disk t since n formatted
    declare -A brdisk first
    # One worker at a time; a lock left by a killed worker is taken over.
    if ! mkdir "$lock" 2>/dev/null; then
        t=$(cat "$lock/pid" 2>/dev/null || true)
        if [[ $t =~ ^[1-9][0-9]*$ ]]; then
            kill -0 "$t" 2>/dev/null && return 0
        elif [[ -z $(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null) ]]; then
            return 0 # just taken, its pid not written yet
        fi
        rm -rf "$lock"; mkdir "$lock" 2>/dev/null || return 0
    fi
    echo $$ >"$lock/pid" || return 0
    touch "$seen"
    new=$(kernel_log_raw | grep -E '\] I/O error, dev [a-z0-9]+, .*\(WRITE\)' | grep -vxFf "$seen" || true)
    if [[ -n $new ]]; then
        for br in $(pool_branches); do
            part=$(findmnt -n -o SOURCE "$MIG/mnt/hd-$br" 2>/dev/null) || continue
            disk=$(lsblk -no PKNAME "$part" 2>/dev/null | head -n 1)
            brdisk[${disk:-${part#/dev/}}]=$br
        done
        while IFS= read -r line; do
            dev=$(sed -E 's/.*I\/O error, dev ([a-z0-9]+),.*/\1/' <<<"$line")
            br=${brdisk[$dev]:-}
            [[ -n $br && -z ${first[$br]:-} ]] || continue
            t=$(stamp_time "$(sed -E 's/^\[ *([^]]*)\].*/\1/' <<<"$line")") || t=$(date '+%F %T')
            first[$br]=$t
            log "WARN hd-$br ($dev) failed a write at $t: $line"
        done <<<"$new"
        for br in "${!first[@]}"; do
            since=$(date -d "${first[$br]} $WRITE_MARGIN minutes ago" '+%F %T')
            formatted=$(uncopy "$br" "$since")
            if [[ -n $formatted ]]; then
                echo "hd-$br failed a write at ${first[$br]}, and $(echo $formatted) was verified and formatted since $since: nothing was moved aside; compare the files on hd-$br changed since $since with care before going on." >"$MIG/state/stop"
                continue
            fi
            n=$(aside_since "$br" "$since")
            log "WARN hd-$br: $n files changed since $since moved aside on it; the next pass copies them again"
            echo "hd-$br failed a write at ${first[$br]} ($n files changed there since $since moved aside, copied again by the next pass)." >"$MIG/state/stop"
        done
        printf '%s\n' "$new" >>"$seen"
        if [[ -f $MIG/state/stop ]] && sudo tmux has-session -t mig-33 2>/dev/null; then
            sudo tmux kill-session -t mig-33; log "WARN the copy of disk 33 stopped ('extra' starts it again)"
        fi
    fi
    rm -rf "$lock"
}
# aside_since NN SINCE [UNTIL]: move the files changed on hd-NN since SINCE (and not after UNTIL)
# into .migrate-aside on the same disk (a rename: instant, nothing copied or deleted). Prints how many.
aside_since() {
    local root=$MIG/mnt/hd-$1 dir n=0 p bound=()
    dir=.migrate-aside/write-error-$(date '+%Y%m%d-%H%M%S')
    [[ -z ${3:-} ]] || bound=(! -newerct "$3")
    while IFS= read -r -d '' p; do
        sudo mkdir -p "$root/$dir/$(dirname "$p")" && sudo mv -n "$root/$p" "$root/$dir/$p" && n=$((n + 1))
    done < <(sudo timeout 900 find "$root" -xdev -type f ! -path '*/.migrate-aside/*' -newerct "$2" "${bound[@]}" -printf '%P\0' 2>/dev/null)
    echo "$n"
}

# Does branch $1 take a write? A create and remove at its root, 60 s at most (MIG_PROBE): a dead
# disk leaves the call hanging, so it runs in the background and is abandoned, not waited for.
# A branch that is not mounted fails too: a write there would land on the system disk.
branch_ok() {
    local f="$MIG/mnt/hd-$1/.probe.$$" pid i
    findmnt -n "$MIG/mnt/hd-$1" >/dev/null || return 1
    ( sudo sh -c ": >'$f' && rm -f '$f'" ) 2>/dev/null &
    pid=$!
    for ((i = 0; i < ${MIG_PROBE:-60}; i++)); do
        kill -0 "$pid" 2>/dev/null || { wait "$pid"; return; }
        sleep 1
    done
    return 1
}

# Drop every pool branch that does not take a write. A dead branch fails each create the pool
# places on it (EIO), so a pass ends with errors for as many files as it got. New files then go
# to the others, and the files it held are copied again by the next pass (the sources are still
# there). Returns 0 if a branch was dropped.
heal_pool() {
    local br dropped=1
    for br in $(pool_branches); do
        branch_ok "$br" && continue
        log "WARN branch hd-$br does not take a write: out of the pool, marked bad ($MIG/state/$br.bad); 'good $br' puts it back"
        mark_bad "$br"; dropped=0
    done
    return $dropped
}

# The row (A-D) a disk belongs to; ? if none.
row_of() { local r; for r in "${!ROW[@]}"; do [[ " ${ROW[$r]} " == *" $1 "* ]] && { echo "$r"; return; }; done; echo '?'; }

# walk_pool OUT FORMAT [find tests]: every regular file of every pool branch, as find -printf
# "<branch>FORMAT" records into OUT, in branch order. One walk at a time per row (the
# enclosure is the bottleneck, as for copying), the rows side by side. Returns 1, after
# saying which branch, if a walk failed: its files are then missing from OUT.
walk_pool() {
    local out=$1 fmt=$2 r br tmp all rc=0; shift 2
    all=$(pool_branches)
    tmp=$(mktemp -d "$MIG/state/walk.XXXXXX"); walktmp=$tmp
    for r in A B C D '?'; do
        (   for br in $all; do
                [[ $(row_of "$br") == "$r" ]] || continue
                sudo find "$MIG/mnt/hd-$br" -xdev -type f ! -path '*/.migrate-aside/*' "$@" -printf "$br$fmt" >"$tmp/$br" 2>"$tmp/$br.err" \
                    || : >"$tmp/$br.failed"
            done
        ) &
    done
    wait
    for br in $all; do
        if [[ -e $tmp/$br.failed ]]; then
            log "WARN recheck: the walk of hd-$br failed ($(head -n 1 "$tmp/$br.err")); its files are not in this pass"
            rc=1
        fi
        cat "$tmp/$br"
    done >"$out"
    rm -rf "$tmp"; walktmp=""
    return $rc
}

# Flush to disk the pool copies of one source's files (paths relative to the source, "\0"-ended,
# on stdin): an fsync per file, through the pool to the branch that holds it. On XFS the fsync
# also commits the file's directory entry, which sits in the same log. Paths the pool lacks
# (volume files never copied) are counted, not errors.
read -r -d '' FLUSH_PY <<'PY' || true
import os, sys
pool = os.fsencode(sys.argv[1])
done = absent = failed = 0
for rel in sys.stdin.buffer.read().split(b"\0"):
    if not rel:
        continue
    try:
        fd = os.open(os.path.join(pool, rel), os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        absent += 1
        continue
    except OSError as e:
        print("cannot open %s: %s" % (os.fsdecode(rel), e.strerror), file=sys.stderr)
        failed += 1
        continue
    try:
        os.fsync(fd)
        done += 1
    except OSError as e:
        print("fsync %s: %s" % (os.fsdecode(rel), e.strerror), file=sys.stderr)
        failed += 1
    finally:
        os.close(fd)
print("%d files flushed, %d not in the pool, %d failed" % (done, absent, failed))
sys.exit(1 if failed else 0)
PY

# recheck, one source: the pool files in the candidate list (records "<branch>\t<size>\t<path>\0")
# whose path exists in the source and whose size differs, or with "full" whose bytes differ,
# come out as "<branch>\t<path>\0". One process reads the list; no fork per file.
read -r -d '' RECHECK_PY <<'PY' || true
import os, stat, sys
src, cand, mnt, mode = (os.fsencode(a) for a in sys.argv[1:5])
full = mode == b"full"
def same(a, b):
    with open(a, "rb", buffering=0) as fa, open(b, "rb", buffering=0) as fb:
        while True:
            x, y = fa.read(1 << 20), fb.read(1 << 20)
            if x != y:
                return False
            if not x:
                return True
out = sys.stdout.buffer
total = checked = differ = unread = 0
with open(cand, "rb") as fh:
    records = fh.read().split(b"\0")
for rec in records:
    if not rec:
        continue
    total += 1
    br, size, path = rec.split(b"\t", 2)
    s = os.path.join(src, path)
    try:
        st = os.lstat(s)
    except (FileNotFoundError, NotADirectoryError):
        continue
    except OSError as e:
        sys.stderr.write("cannot read %r: %s\n" % (s, e)); unread += 1
        continue
    if not stat.S_ISREG(st.st_mode):
        continue
    checked += 1
    try:
        bad = st.st_size != int(size) or (full and not same(s, os.path.join(mnt, b"hd-" + br, path)))
    except OSError as e:
        sys.stderr.write("cannot compare %r: %s\n" % (s, e)); unread += 1
        continue
    if bad:
        differ += 1
        out.write(br + b"\t" + path + b"\0")
sys.stderr.write("%d of %d pool files are in this source; %d differ, %d could not be read\n" % (checked, total, differ, unread))
sys.exit(3 if unread else 0)
PY

# Add a freshly formatted bay $1 to the pool.
pool_add() {
    local mm=$1 br
    mount_branch "$mm"
    br=$MIG/mnt/hd-$mm
    if findmnt -n "$POOL" >/dev/null; then
        if ! sudo getfattr -n user.mergerfs.branches --only-values "$POOL/.mergerfs" 2>/dev/null | tr ':' '\n' | grep -qx "$br=RW"; then
            sudo setfattr -n user.mergerfs.branches -v "+>$br" "$POOL/.mergerfs"
        fi
    else
        pool_mount >/dev/null
    fi
    log "pool: branches $(pool_branches)"
}

pool_avail() { avail_at "$POOL"; }

# Free pool space minus what the other workers' running copies still need.
pool_room() {
    local c nn r=0
    for c in "$MIG"/state/claim-*/need; do
        [[ -f $c ]] || continue
        nn=${c%/need}; nn=${nn##*/claim-}
        [[ $nn != "$1" ]] && claimed "$nn" && r=$((r + $(cat "$c")))
    done
    echo $(( $(pool_avail) - r ))
}

# Reserve $2 bytes of room for source $1 if the pool has them, under a lock so two workers
# cannot both take the last room. Returns 1 when there is not enough.
reserve_room() {
    local ok=1
    until mkdir "$MIG/state/lock-room" 2>/dev/null; do sleep 2; done
    if (($(pool_room "$1") >= $2)); then
        echo "$2" >"$MIG/state/claim-$1/need"
        ok=0
    fi
    rmdir "$MIG/state/lock-room"
    return $ok
}

# $1 row, $2 source name: copy the source into the pool.
copy_disk() {
    local nn=$2 src dst s pass rc dropped flushed rpid i
    stopped
    src=$MIG/mnt/src-$nn
    dst=$POOL
    s=$(part_of "$(disk_of "$nn")") || exit 1
    [[ $(fstype_of "$s") == "$SRC_FS" ]] || die "$nn is not $SRC_FS any more"
    findmnt -n "$dst" >/dev/null || die "pool is not mounted"
    mount_at "$nn" "$s" "$src" ro
    log "$nn>pool: copying $(used_at "$src") bytes from $s; pool has $(pool_avail) free"
    heal_pool || true
    pass=0
    while ((pass < 3)); do
        pass=$((pass + 1)); rc=0
        # Extended attributes: all but system.* and the Apple ones (osx.*: Finder info,
        # quarantine, provenance, Spotlight metadata), which the hfsplus driver lists under
        # truncated names it cannot read back; security.* (SELinux labels) on the XFS side
        # are left alone, not deleted.
        mapfile -t vx < <(volume_excludes)
        sudo rsync -aHAX --filter='-x system.*' --filter='-x osx.*' --filter='-xr security.*' "${vx[@]}" \
            --ignore-existing --info=progress2,stats1 --no-inc-recursive "$src/" "$dst/" >>"$LOG" 2>&1 &
        rpid=$!
        # While it copies: every MIG_WATCH seconds, a failed write on a pool branch stops it.
        while [[ -e /proc/$rpid ]]; do
            for ((i = 0; i < ${MIG_WATCH:-60}; i++)); do [[ -e /proc/$rpid ]] || break; sleep 1; done
            check_writes
            [[ ! -f $MIG/state/stop ]] || sudo kill -TERM "$rpid" 2>/dev/null || true
        done
        wait "$rpid" || rc=$?
        stopped
        # 23/24: some files could not be read or vanished; those are listed in the log.
        log "$nn>pool: rsync pass $pass finished with code $rc"
        [[ $rc == 0 ]] && break
        # A branch that stopped answering fails the creates placed on it: 23, or 11 when it dies
        # mid-file. Drop it and run the pass again (a repair does not use up one of the three).
        dropped=""; heal_pool && dropped=1
        if [[ -n $dropped ]]; then
            [[ -n $(pool_branches) ]] || die "$nn>pool: no pool branch takes a write; see $LOG. Source untouched."
            pass=$((pass - 1)); continue
        fi
        [[ $rc == 23 || $rc == 24 ]] || die "$nn>pool: rsync failed (code $rc); see $LOG. Source untouched."
    done
    [[ $rc == 0 ]] || die "$nn>pool: files could not be copied after three passes; see $LOG. Source untouched."
    # Only this source's copies: a global sync also waits for every other writer (the other
    # workers, disk 33) and held row D for hours on 16 Oct. The source may be formatted once
    # verified, so its copies must be on disk first.
    log "$nn>pool: flushing its copies to disk"
    flushed=$(sudo find "$src" -xdev -type f -printf '%P\0' | sudo python3 -I -c "$FLUSH_PY" "$dst" 2>>"$LOG") ||
        die "$nn>pool: some copies could not be flushed ($flushed); see $LOG. Source untouched."
    log "$nn>pool: $flushed"
    log "$nn>pool: copy done; pool has $(pool_avail) free"
}

# $1 row, $2 source: read every file of the source back from the pool and compare.
verify_disk() {
    local row=$1 nn=$2 src dst diff opts
    src=$MIG/mnt/src-$nn
    dst=$POOL
    check_writes; stopped
    if [[ $VERIFY == quick ]]; then
        opts=(-rln --times --size-only)
        log "$nn>pool: verifying by size and time"
    else
        opts=(-rlnc)
        log "$nn>pool: verifying every file by checksum (reads the source and its copy in full)"
    fi
    # No --delete: the pool also holds the other sources' files. Folders are not compared: one
    # merged from several sources, or written into by other workers, has one time in the pool.
    mapfile -t vx < <(volume_excludes)
    diff=$(sudo rsync "${opts[@]}" "${vx[@]}" --out-format='%n' "$src/" "$dst/" 2>&1 | grep -v -e '^\./$' -e '/$' || true)
    if [[ -n $diff ]]; then
        printf '%s\n' "$diff" >>"$MIG/state/$nn.differences"
        die "$nn>pool: $(wc -l <<<"$diff") files differ or are missing in the pool (a same-named file from another disk?); see $MIG/state/$nn.differences. Source untouched."
    fi
    local nsrc
    nsrc=$(sudo find "$src" -xdev -type f | wc -l)
    sudo umount "$src"
    echo "copied to the pool by worker $row, $nsrc files, verified $VERIFY $(date '+%F %T')" >"$MIG/state/$nn.copied"
    echo "$nn -> pool  $nsrc files  $(date '+%F %T')  branches then: $(pool_branches)" >>"$MIG/state/placement.txt"
    log "$nn>pool: verified, $nsrc files. $nn may now be formatted and join the pool."
}

# ---- the scheduler ----------------------------------------------------------------------

# Claims keep two workers off the same disk; a claim is a directory, made atomically, with
# the worker's pid inside. A claim whose worker is gone (killed, crashed, died on an error)
# is stale and is swept away wherever claims are read, so a restart never waits on a ghost.
# A claim with a "need" file inside is a running copy that has reserved pool space.
claim() { claimed "$1" && return 1; mkdir "$MIG/state/claim-$1" 2>/dev/null || return 1; echo $$ >"$MIG/state/claim-$1/pid"; }
release() { rm -rf "$MIG/state/claim-$1"; }
# True when $1 is claimed by a living worker; a stale claim is removed.
claimed() {
    local c=$MIG/state/claim-$1 pid
    [[ -d $c ]] || return 1
    pid=$(cat "$c/pid" 2>/dev/null || echo none) # none: made by a version before pids
    if [[ $pid == "$$" ]] || { [[ $pid =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; }; then return 0; fi
    log "claim on $1 by worker $pid, which is gone: removed"
    rm -rf "$c"
    return 1
}
# True when some other disk than $1 is claimed by a living worker.
others_claimed() {
    local c
    for c in "$MIG"/state/claim-*; do
        [[ -d $c && ${c##*/claim-} != "$1" ]] && claimed "${c##*/claim-}" && return 0
    done
    return 1
}

# Prints "nn USED" for every HFS+ disk of row $1 not yet copied and not claimed, smallest
# first, the parity disk last, a deferred disk after that.
sources_of() {
    local nn st
    for nn in ${ROW[$1]}; do
        [[ -f $MIG/state/$nn.copied ]] && continue
        claimed "$nn" && continue
        st=$(disk_state "$nn")
        [[ $st == src* ]] || continue
        if ((${st#src } < EMPTY_LIMIT)); then
            # Under 1 GB: nothing worth a copy; it may be formatted like a copied disk.
            echo "empty, nothing to copy $(date '+%F %T')" >"$MIG/state/$nn.copied"
            continue
        fi
        # The parity disk frees no bay when copied, so it goes last whatever its size; a
        # deferred disk (flaky link) after everything else.
        if [[ -f $MIG/state/$nn.deferred ]]; then echo "$nn ${st#src } z-deferred"
        elif [[ $nn == "${PARITY[$1]}" ]]; then echo "$nn ${st#src } last"
        else echo "$nn ${st#src } first"; fi
    done | sort -k3,3 -k2,2n | cut -d' ' -f1,2
}

# Prints a disk that may be formatted now: one this script emptied by a verified copy (or
# you marked with "erase") and has not reformatted, row $1 first, then the other rows;
# else, before row $1's first round, its last bay (the old parity disk, which asks for
# confirmation); else nothing.
formattable_of() {
    local row nn
    for row in "$1" A B C D; do
        for nn in ${ROW[$row]}; do
            [[ $nn == "${PARITY[$row]}" ]] && continue
            [[ -e $MIG/state/$nn.bad ]] && continue
            claimed "$nn" && continue
            if [[ -f $MIG/state/$nn.copied ]] && [[ $(disk_state "$nn") == src* ]]; then
                echo "$nn"
                return
            fi
        done
    done
    [[ -f $MIG/state/row-$1.started || -e $MIG/state/${ROW[$1]##* }.bad ]] || echo "${ROW[$1]##* }"
}

# One worker: rounds until no source is left.
run_row() {
    local row=$1 src used tgt need line
    pool_mount >/dev/null 2>&1 || true
    heal_pool || true
    while true; do
        line=$(sources_of "$row" | head -n 1)
        if [[ -z $line ]]; then
            log "row $row: no source left for this worker"
            break
        fi
        read -r src used <<<"$line"
        need=$((used + used / 1000 + 1000000000)) # 0.1 % and 1 GB of slack
        claim "$src" || { sleep 60; continue; }
        # Enough room in the pool, after the other workers' running copies? Otherwise format
        # a bay and add it, as long as one is free; else wait for the other workers to free
        # one (a wait with no other worker at all is a dead end).
        while ! findmnt -n "$POOL" >/dev/null || ! reserve_room "$src" "$need"; do
            tgt=$(formattable_of "$row")
            if [[ -z $tgt ]]; then
                if others_claimed "$src"; then
                    log "row $row: pool too small for $src ($used bytes) and no bay to add yet; waiting for other workers"
                    sleep "$WAIT"
                    continue
                fi
                release "$src"
                die "row $row: pool too small for $src ($used bytes) and no bay left to add. See placement.txt."
            fi
            claim "$tgt" || { sleep 60; continue; }
            format_target "$tgt"
            touch "$MIG/state/row-$row.started"
            pool_add "$tgt"
            release "$tgt"
        done
        log "round: $src ($used bytes) -> pool ($(pool_avail) free, $(pool_room "$src") after reservations)"
        copy_disk "$row" "$src"
        verify_disk "$row" "$src"
        release "$src"
    done
    # Every copied bay of the row that is still HFS+ joins the pool now, so the row ends complete.
    for src in ${ROW[$row]}; do
        [[ $src == "${PARITY[$row]}" ]] && continue
        if [[ -f $MIG/state/$src.copied && $(disk_state "$src") == src* ]] && claim "$src"; then
            format_target "$src"
            pool_add "$src"
            release "$src"
        fi
    done
    # The parity disk: once its content is copied it holds nothing we need.
    if [[ -f $MIG/state/${PARITY[$row]}.copied && $(disk_state "${PARITY[$row]}") == src* ]] && claim "${PARITY[$row]}"; then
        log "row $row: formatting parity disk ${PARITY[$row]}"
        format_target "${PARITY[$row]}"
        release "${PARITY[$row]}"
    fi
    log "row $row: worker finished; pool: $(pool_branches)"
}

# ---- front ------------------------------------------------------------------------------

# A worker's tmux session outlives it: it ends in "worker ended; press enter".
worker_ended() { sudo tmux capture-pane -p -t "$1" 2>/dev/null | grep -q '^worker ended; press enter'; }

need_row() { [[ -n ${1:-} && -n ${ROW[$1]:-} ]] || die "row must be A, B, C or D"; }

prepare() {
    [[ -r $PLAN ]] || die "no $PLAN; run disk-inventory.sh first"
    ! grep -q ',?$' "$PLAN" || die "$PLAN still has unnamed disks"
    [[ $(tail -n +2 "$PLAN" | cut -d, -f14 | sort | uniq -d | wc -l) == 0 ]] || die "$PLAN names a disk twice; run disk-inventory.sh again"
    [[ $(tail -n +2 "$PLAN" | wc -l) == 32 ]] || echo "WARN: $PLAN lists $(tail -n +2 "$PLAN" | wc -l) disks, not 32"
    mkdir -p "$MIG/state" "$MIG/mnt"
    for t in mkfs.xfs rsync parted tmux setfattr; do
        command -v "$t" >/dev/null || sudo dnf install -y xfsprogs rsync parted tmux attr
    done
    command -v "$MERGERFS" >/dev/null || die "no mergerfs; run '$0 mergerfs' once to build and install it"
    sudo -v
}

case ${1:-} in
plan)
    need_row "${2:-}"
    prepare
    LOG=/dev/null
    echo "row $2, parity ${PARITY[$2]}:"
    for nn in ${ROW[$2]}; do
        st=$(disk_state "$nn")
        printf '  %s  %-14s %-8s' "$nn" "$(readlink -f "$(disk_of "$nn")")" "${st%% *}"
        awk -v s="$st" 'BEGIN { split(s, f, " "); if (f[1] == "src") printf "%.2f TB used", f[2] / 1e12; else if (f[1] == "xfs") printf "%.2f TB used, %.2f TB free", f[2] / 1e12, f[3] / 1e12; else printf "%s", s }'
        [[ -f $MIG/state/$nn.copied ]] && printf '  (%s)' "$(cat "$MIG/state/$nn.copied")"
        [[ -f $MIG/state/$nn.deferred ]] && printf '  deferred: copied last'
        [[ -f $MIG/state/$nn.dirty ]] && printf '  DIRTY: holds a failed copy'
        echo
    done
    nsets=$(sources_of "$2" | wc -l)
    ((nsets <= 7)) || echo "  WARN: $nsets disks hold data and the row has 7 bays for it: the last bay (${ROW[$2]##* }) will be erased without a copy, after you confirm"
    echo "  copies, smallest source first (the parity disk last, deferred disks after it):"
    sources_of "$2" | awk '{ printf "    %s (%.2f TB)\n", $1, $2 / 1e12 }'
    echo "  pool branches now (all rows): $(branches_of | tr '\n' ' ')"
    findmnt -n "$POOL" >/dev/null && echo "  pool mounted at $POOL: $(df -h --output=avail "$POOL" | tail -n 1 | tr -d ' ') free"
    echo "  formatted without asking when needed (under $((EMPTY_LIMIT / 1000000)) MB, or marked by 'erase'): $(for nn in ${ROW[$2]}; do [[ -f $MIG/state/$nn.copied ]] && grep -qE '^(empty|erase)' "$MIG/state/$nn.copied" && printf '%s ' "$nn"; done)"
    f=$(formattable_of "$2")
    if [[ -n $f && -f $MIG/state/$f.copied ]]; then
        echo "  first bay added to the pool: $f (empty, without asking)"
    elif [[ -n $f ]]; then
        echo "  first bay added to the pool: $f (holds data that will NOT be copied; asks for 'erase $f')"
    else
        echo "  first bay added to the pool: none needed now"
    fi
    ;;
pool)
    prepare
    LOG=/dev/null
    pool_mount && echo "pool mounted at $POOL: $(pool_branches)" || echo "no formatted bay yet"
    ;;
recheck)
    # Why: a copy skips files that already exist in the pool (--ignore-existing), so a file
    # left short by a dying disk, or written twice because a dead branch looked empty, would
    # be kept as it is. Every suspect copy goes to .migrate-aside/<source>/<path> on the
    # same disk; the log says which. Sources must be idle (no worker running).
    shift
    [[ $# -gt 0 ]] || die "recheck needs source names, e.g. recheck 26 27 02 05 10 13 18 19 20"
    if [[ $EUID != 0 ]]; then
        # A long run: as root, so that no sudo ticket runs out under it (a byte compare outlasts
        # the 5 minutes) and so that Ctrl-C reaches every process of it.
        envs=(HOME="$HOME" MIG_HOME="$MIG" MIG_PLAN="$PLAN" MIG_SRC_FS="$SRC_FS" MIG_EMPTY_LIMIT="$EMPTY_LIMIT"
            MIG_MINFREE="$MINFREE" MIG_CREATE="$CREATE" MIG_MERGERFS="$MERGERFS" MIG_WAIT="$WAIT" VERIFY="$VERIFY")
        for v in MIG_RECHECK_SINCE MIG_RECHECK_UNTIL MIG_RECHECK_DUPS; do [[ -z ${!v+x} ]] || envs+=("$v=${!v}"); done
        exec sudo env "${envs[@]}" bash "$0" recheck "$@"
    fi
    prepare
    LOG=$MIG/recheck.log
    # Ctrl-C (or a closed terminal): stop every process of this run, which the background jobs
    # would otherwise outlive, and let go of the sources.
    declare -A parts chain
    stop() {
        trap '' INT TERM HUP; kill -TERM 0 2>/dev/null; sleep 1
        for nn in "${!parts[@]}"; do umount "$MIG/mnt/src-$nn" 2>/dev/null || true; done
        [[ -z ${walktmp:-} ]] || rm -rf "$walktmp"; [[ -z ${tmp:-} ]] || rm -rf "$tmp"
        log "recheck: interrupted"; exit 130
    }
    trap stop INT TERM HUP
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-[A-D]-' || die "workers still run; sudo tmux kill-server first"
    pool_mount >/dev/null || die "no pool"
    aside=0; incomplete=0
    # 1. The same path on two branches: the copy on the branch that comes first in the pool
    #    hides the other. Both are kept; the first one goes aside, the next pass compares.
    # The two-branch pass is global; several rechecks at once (one per source, in parallel)
    # run it only in one of them: MIG_RECHECK_DUPS=0 in the others.
    if [[ ${MIG_RECHECK_DUPS:-1} == 1 ]]; then
    log "recheck: looking for paths present on two branches"
    seen=$MIG/state/recheck.paths; prev=""; prevbr=""
    walk_pool "$seen" '\t%P\0' || incomplete=1
    while IFS= read -r -d '' rec; do
        br=${rec%%$'\t'*}; path=${rec#*$'\t'}
        [[ $path == "$prev" ]] || { prev=$path; prevbr=$br; continue; }
        # second branch with the same path: move the earlier one (lower in branch order) aside
        to="$MIG/mnt/hd-$prevbr/.migrate-aside/dup/$path"
        sudo mkdir -p "$(dirname "$to")"; sudo mv "$MIG/mnt/hd-$prevbr/$path" "$to"
        log "recheck: '$path' on $prevbr and $br; the $prevbr copy moved aside"
        aside=$((aside + 1)); prev=$path; prevbr=$br
    done < <(LC_ALL=C sort -z -s -t$'\t' -k2 "$seen")
    fi
    # 2. Checksum of every file of each source that has a copy in the pool; or, with
    #    MIG_RECHECK_SINCE="YYYY-MM-DD HH:MM", only the pool files whose inode changed since then
    #    (rsync sets the times last, so a file finished before SINCE is untouched; a dying disk
    #    only leaves short the files it wrote last). That one compares sizes (VERIFY=quick, the
    #    default: XFS records a size only for data that reached the disk, so a lost write leaves
    #    a short file) or, with VERIFY=full, bytes. Rows run side by side, a row's sources one
    #    after the other.
    if [[ -n ${MIG_RECHECK_SINCE:-} ]]; then
        cand=$MIG/state/recheck.recent
        win=(-newerct "$MIG_RECHECK_SINCE"); [[ -z ${MIG_RECHECK_UNTIL:-} ]] || win+=(! -newerct "$MIG_RECHECK_UNTIL")
        walk_pool "$cand" '\t%s\t%P\0' "${win[@]}" || incomplete=1
        log "recheck: $(tr -cd '\0' <"$cand" | wc -c) pool files written between $MIG_RECHECK_SINCE and ${MIG_RECHECK_UNTIL:-now}; comparing their $([[ $VERIFY == full ]] && echo bytes || echo sizes) with the sources"
        for nn in "$@"; do
            [[ $nn =~ ^[0-3][0-9]$ ]] || die "$nn is not a disk name"
            part=$(part_of "$(disk_of "$nn")") || exit 1
            [[ $(fstype_of "$part") == "$SRC_FS" ]] || { log "recheck: $nn is not $SRC_FS any more, nothing to compare"; continue; }
            parts[$nn]=$part; chain[$(row_of "$nn")]+=" $nn"
        done
        tmp=$(mktemp -d "$MIG/state/recheck.XXXXXX")
        for r in "${!chain[@]}"; do
            (   moved=0
                for nn in ${chain[$r]}; do
                    src=$MIG/mnt/src-$nn
                    mount_at "$nn" "${parts[$nn]}" "$src" ro
                    rc=0; sudo python3 -I -c "$RECHECK_PY" "$src" "$cand" "$MIG/mnt" "$VERIFY" >"$tmp/bad.$nn" 2>"$tmp/info.$nn" || rc=$?
                    while IFS= read -r line; do log "recheck: $nn: $line"; done <"$tmp/info.$nn"
                    [[ $rc == 0 ]] || { log "WARN recheck: $nn: not every file could be checked (see above)"; : >"$tmp/incomplete.$nn"; }
                    while IFS= read -r -d '' rec; do
                        br=${rec%%$'\t'*}; path=${rec#*$'\t'}
                        to="$MIG/mnt/hd-$br/.migrate-aside/$nn/$path"
                        sudo mkdir -p "$(dirname "$to")"; sudo mv "$MIG/mnt/hd-$br/$path" "$to"
                        log "recheck: $nn: '$path' differs from the source; the $br copy moved aside"
                        moved=$((moved + 1))
                    done <"$tmp/bad.$nn"
                    sudo umount "$src"
                done
                echo "$moved" >"$tmp/done.$r"
            ) &
        done
        wait
        for r in "${!chain[@]}"; do
            if [[ -f $tmp/done.$r ]]; then aside=$((aside + $(<"$tmp/done.$r"))); else log "WARN recheck: row $r stopped early; run it again"; incomplete=1; fi
        done
        compgen -G "$tmp/incomplete.*" >/dev/null && incomplete=1
        rm -rf "$tmp"
        log "recheck: $aside copies moved aside; the next copy pass rewrites them. Remove .migrate-aside folders when the row is verified."
        [[ $incomplete == 0 ]] || { log "WARN recheck: INCOMPLETE, some files were not checked; see the WARN lines"; exit 1; }
        exit 0
    fi
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ ]] || die "$nn is not a disk name"
        part=$(part_of "$(disk_of "$nn")") || exit 1
        [[ $(fstype_of "$part") == "$SRC_FS" ]] || { log "recheck: $nn is not $SRC_FS any more, nothing to compare"; continue; }
        src=$MIG/mnt/src-$nn
        mount_at "$nn" "$part" "$src" ro
        log "recheck: $nn: comparing by checksum every file that is already in the pool"
        while IFS= read -r path; do
            [[ -n $path && $path != */ ]] || continue
            for br in $(pool_branches); do
                f="$MIG/mnt/hd-$br/$path"
                [[ -f $f ]] || continue
                # Each branch copy on its own: one may be whole while another is short.
                sudo cmp -s "$src/$path" "$f" && continue
                to="$MIG/mnt/hd-$br/.migrate-aside/$nn/$path"
                sudo mkdir -p "$(dirname "$to")"; sudo mv "$f" "$to"
                log "recheck: $nn: '$path' differs from the source; the $br copy moved aside"
                aside=$((aside + 1))
            done
        done < <(mapfile -t vx < <(volume_excludes); sudo rsync -rlc --existing --dry-run --out-format='%n' --filter='-x *' "${vx[@]}" "$src/" "$POOL/" 2>>"$LOG" | grep -v '^\./$' || true)
        sudo umount "$src"
    done
    log "recheck: $aside copies moved aside; the next copy pass rewrites them. Remove .migrate-aside folders when the row is verified."
    ;;
finish)
    prepare
    LOG=/dev/null
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-[A-D]-' && true || die "workers still run: $(sudo tmux ls | grep -o '^mig-[A-D]-[0-9]' | tr '\n' ' ')"
    left=""
    for row in A B C D; do for nn in ${ROW[$row]}; do [[ $(disk_state "$nn") == xfs* ]] || left+="$nn "; done; done
    [[ -z $left ]] || die "not XFS yet: $left(parity disks are formatted by their row's worker at its end; a source still HFS+ was not copied)"
    for row in A B C D; do for nn in ${ROW[$row]}; do [[ -f $MIG/state/$nn.differences ]] && echo "WARN: $nn.differences exists; a verify once failed, see it"; done; done
    # Volume bookkeeping copied before it was excluded goes to .migrate-aside/volume on its disk.
    for br in $(branches_of); do
        for f in "${VOLUME_FILES[@]}"; do
            for g in "$MIG/mnt/hd-$br"$f; do
                [[ -e $g ]] || continue
                sudo mkdir -p "$MIG/mnt/hd-$br/.migrate-aside/volume"; sudo mv "$g" "$MIG/mnt/hd-$br/.migrate-aside/volume/"
                echo "$br: ${g##*/hd-$br} moved to .migrate-aside/volume (HFS+ bookkeeping, not data)"
            done
        done
    done
    sudo umount "$POOL" 2>/dev/null || true
    for m in $(findmnt -rn -o TARGET | grep "^$MIG/mnt/" | sort -r); do sudo umount "$m"; done
    # The workers ran as root; the logs and state go back to you.
    sudo chown -R "${SUDO_USER:-$USER}:" "$MIG"
    echo "every disk is XFS; migration mounts released. Logs and placement stay in $MIG, yours again."
    echo "Next: snapraid-setup.sh install, then mount, then first."
    ;;
add)
    # Format now, do not wait for a worker to need the room. Refuses a disk that still holds
    # uncopied data; use "erase" first if that is what you want.
    shift
    [[ $# -gt 0 ]] || die "add needs disk names, e.g. add 23"
    prepare
    LOG=$MIG/add.log
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ && -n $(disk_of "$nn" 2>/dev/null) ]] || die "$nn is not a disk in $PLAN"
        for row in A B C D; do [[ $nn == "${PARITY[$row]}" ]] && die "$nn is a parity disk; it is formatted last by its row's worker"; done
        [[ -f $MIG/state/$nn.copied ]] || [[ $(disk_state "$nn") == xfs* ]] || die "$nn holds data this script has not copied; 'erase $nn' first if its content is not needed"
        claim "$nn" || die "$nn is claimed by a worker; try later"
        format_target "$nn"
        pool_add "$nn"
        release "$nn"
    done
    echo "pool: $(pool_branches)"
    ;;
defer)
    # Copied after everything else in its row; nothing else changes.
    shift
    [[ $# -gt 0 ]] || die "defer needs disk names, e.g. defer 28"
    prepare
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ && -n $(disk_of "$nn" 2>/dev/null) ]] || die "$nn is not a disk in $PLAN"
        touch "$MIG/state/$nn.deferred"
        echo "$nn: deferred, copied last in its row"
    done
    ;;
mergerfs)
    # Fedora 44 ships no mergerfs. Build the upstream release and install it with its own
    # Makefile ("make uninstall" in ~/migrate/build/mergerfs removes it). Not an RPM: the
    # project's rpm target chowns a setuid helper, which only works as root.
    sudo dnf install -y git gcc-c++ make which libatomic
    mkdir -p "$MIG/build"
    [[ -d $MIG/build/mergerfs ]] || git -C "$MIG/build" clone -q --depth 1 --branch "$MERGERFS_TAG" https://github.com/trapexit/mergerfs
    git -C "$MIG/build/mergerfs" describe --tags | grep -q "^$MERGERFS_TAG$" || die "$MIG/build/mergerfs is not at $MERGERFS_TAG; remove it and rerun"
    make -C "$MIG/build/mergerfs" -j"$(nproc)"
    sudo make -C "$MIG/build/mergerfs" install PREFIX=/usr
    mergerfs --version | head -n 1
    ;;
stats)
    # Fill per branch from df; throughput per disk from /proc/diskstats (sectors of 512 B).
    secs=${2:-5}
    findmnt -n "$POOL" >/dev/null || die "pool not mounted"
    printf 'pool: %s\n' "$(df -h --output=size,used,avail,pcent "$POOL" | tail -n 1)"
    declare -A r0 w0
    # Whole sd disks only (sda, sdaa; not partitions, not nvme/zram/loop).
    while read -r _ _ d _ _ r _ _ _ w _; do
        [[ $d == sd* && $d != *[0-9] ]] || continue
        r0[$d]=$r; w0[$d]=$w
    done </proc/diskstats
    sleep "$secs"
    while read -r _ _ d _ _ r _ _ _ w _; do
        [[ $d == sd* && $d != *[0-9] && -n ${r0[$d]:-} ]] || continue
        rd=$(( (r - r0[$d]) * 512 / secs / 1000000 )); wr=$(( (w - w0[$d]) * 512 / secs / 1000000 ))
        ((rd + wr > 0)) || continue
        src=$(findmnt -n -o SOURCE,TARGET -l | grep "^/dev/$d" | grep -oE 'mnt/(hd|src)-[0-9]+' | head -n 1 || true)
        printf '%-6s %-9s read %4d MB/s  write %4d MB/s\n' "$d" "${src#mnt/}" "$rd" "$wr"
    done </proc/diskstats | sort -k2
    echo "branches:"
    for d in "$MIG"/mnt/hd-*; do
        findmnt -n "$d" >/dev/null || continue
        printf '    %s %s\n' "${d##*/hd-}" "$(df -h --output=size,used,avail,pcent "$d" | tail -n 1)"
    done
    ;;
erase)
    # Your decision, written down: the disk counts as copied, so a worker formats it without
    # a copy and without a prompt. Shows what the disk holds, so a wrong name is seen now.
    shift
    [[ $# -gt 0 ]] || die "erase needs disk names, e.g. erase 07 15 23 31"
    prepare
    LOG=/dev/null
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ && -n $(disk_of "$nn" 2>/dev/null) ]] || die "$nn is not a disk in $PLAN"
        st=$(disk_state "$nn")
        case $st in
        src*)
            [[ -f $MIG/state/$nn.copied ]] && { echo "$nn: already marked: $(cat "$MIG/state/$nn.copied")"; continue; }
            echo "erase: not needed, says the operator $(date '+%F %T')" >"$MIG/state/$nn.copied"
            printf '%s: %s, %.2f TB on %s, marked: will be formatted without a copy\n' "$nn" "$(readlink -f "$(disk_of "$nn")")" "$(awk -v u="${st#src }" 'BEGIN { print u / 1e12 }')" "$SRC_FS"
            ;;
        xfs*) echo "$nn: already XFS, nothing to mark" ;;
        *) die "$nn: $st; not a $SRC_FS disk" ;;
        esac
    done
    ;;
run)
    need_row "${2:-}"
    prepare
    LOG=$MIG/$2.log
    trust_again
    log "row $2: worker start (VERIFY=$VERIFY)"
    run_row "$2"
    ;;
start)
    # start [ROW|all] [N]: without a row, every row. A worker that ended (an error, a dead disk)
    # gets a fresh one, a running one is left alone; dead pool branches are dropped first.
    rows=${2:-all}
    if [[ $rows == all ]]; then rows="A B C D"; else need_row "$rows"; fi
    prepare
    n=${3:-1}
    [[ $n =~ ^[1-4]$ ]] || die "workers: 1 to 4"
    LOG=$MIG/heal.log
    trust_again
    if pool_mount >/dev/null; then heal_pool || true; fi
    for row in $rows; do
        for i in $(seq 1 "$n"); do
            if sudo tmux has-session -t "mig-$row-$i" 2>/dev/null; then
                if worker_ended "mig-$row-$i"; then
                    sudo tmux kill-session -t "mig-$row-$i"
                    echo "worker mig-$row-$i had ended; its session is replaced"
                else
                    echo "worker mig-$row-$i is already running"
                    continue
                fi
            fi
            # The worker holds a sleep inhibitor: a suspend would drop the tunnels mid-copy.
            inhibit=""; sudo systemd-inhibit --what=sleep:idle --who=migrate-row --why=probe true 2>/dev/null && inhibit="systemd-inhibit --what=sleep:idle --who=migrate-row --why='row $row copying'"
            # The inner shell is root's: HOME and the hooks are passed on explicitly.
            sudo tmux new-session -d -s "mig-$row-$i" "HOME='$HOME' MIG_HOME='$MIG' MIG_PLAN='$PLAN' MIG_MERGERFS='$MERGERFS' MIG_SRC_FS='$SRC_FS' MIG_EMPTY_LIMIT='$EMPTY_LIMIT' MIG_MINFREE='$MINFREE' MIG_WAIT='$WAIT' VERIFY=$VERIFY $inhibit '$0' run $row; echo; echo 'worker ended; press enter'; read"
            echo "row $row worker $i started in tmux session mig-$row-$i (root's tmux)"
            [[ $i == 1 && $n -gt 1 ]] && sleep 20 # let the first one take the confirmation prompt
        done
    done
    bad=$(cd "$MIG/state" 2>/dev/null && ls ./*.bad 2>/dev/null | sed 's|^\./||; s|\.bad$||' | tr '\n' ' ' || true)
    [[ -z $bad ]] || echo "out of the pool (bad): $bad- 'good NN' puts one back once it answers"
    echo "Watch: $0 attach ROW [N] (Ctrl-b d to leave); progress: $0 status"
    ;;
attach) sudo tmux attach -t "mig-${2:-}-${3:-1}" ;;
pause | resume)
    # pause ROW... | all: stop a row's worker where it is (rsync mid-file included), resume goes on.
    # 33 is the copy of disk 33. Nothing times out meanwhile; a paused worker does not watch for
    # failed writes, the others do.
    cmd=$1; shift
    [[ $# -gt 0 ]] || die "$cmd needs rows, e.g. $cmd A, $cmd A C, $cmd all (33: disk 33)"
    LOG=$MIG/heal.log; mkdir -p "$MIG/state"
    rows=$*; [[ $rows == all ]] && rows="A B C D 33"
    for r in $rows; do
        [[ $r =~ ^([ABCD]|33)$ ]] || die "$r is not a row (A, B, C, D) or 33"
        if [[ $cmd == pause ]]; then pause_row "$r"; else resume_row "$r"; fi
    done
    ;;
rest)
    # rest MINUTES | off: the rows take turns to rest, one at a time, MINUTES each (15: every box
    # rests 15 minutes an hour, the copies run 25 % slower), in root's tmux session mig-rest.
    # off ends it and resumes every row.
    LOG=$MIG/heal.log; mkdir -p "$MIG/state"
    case ${2:-} in
    off)
        sudo tmux kill-session -t mig-rest 2>/dev/null || true
        rm -f "$MIG/state/rest"
        for r in A B C D 33; do [[ -f $MIG/state/paused-$r ]] && resume_row "$r"; done
        log "rest: off, every row runs"
        ;;
    '' | *[!0-9]*) die "rest MINUTES (e.g. rest 15) or rest off" ;;
    *)
        sudo tmux kill-session -t mig-rest 2>/dev/null || true
        echo "$2" >"$MIG/state/rest"
        sudo tmux new-session -d -s mig-rest "HOME='$HOME' MIG_HOME='$MIG' MIG_PLAN='$PLAN' MIG_REST_UNIT='${MIG_REST_UNIT:-60}' '$0' rest-loop $2"
        log "rest: rows take turns, $2 minutes each, in tmux session mig-rest"
        ;;
    esac
    ;;
rest-loop)
    # The turns themselves (started by 'rest'): a row with no worker is skipped at once.
    LOG=$MIG/heal.log
    trap 'resume_row "${r:-}"; exit 0' INT TERM HUP
    while true; do
        for r in A B C D; do
            [[ -n $(row_pids "$r") ]] || continue
            pause_row "$r"
            sleep $(($2 * ${MIG_REST_UNIT:-60}))
            resume_row "$r"
        done
        sleep 1
    done
    ;;
policy)
    if [[ -n ${2:-} ]]; then
        [[ $2 =~ ^(pfrd|mfs|lfs|lus|rand|ff|epmfs|eppfrd|msppfrd|mspmfs)$ ]] || die "unknown policy $2; pfrd or mfs are the useful ones here"
        mkdir -p "$MIG/state"
        echo "$2" >"$MIG/state/create"
        if findmnt -n "$POOL" >/dev/null; then
            sudo setfattr -n user.mergerfs.category.create -v "$2" "$POOL/.mergerfs"
        fi
        LOG=$MIG/heal.log
        log "pool: new files placed by $2 from now on"
    fi
    echo "kept: $(cat "$MIG/state/create" 2>/dev/null || echo 'pfrd (default)')"
    if findmnt -n "$POOL" >/dev/null; then
        echo "live: $(sudo getfattr -n user.mergerfs.category.create --only-values "$POOL/.mergerfs" 2>/dev/null)"
    else
        echo "live: pool not mounted"
    fi
    ;;
readtest)
    need_row "${2:-}"
    row=$2; ss=test-$row; st=$MIG/state/readtest-$row
    mkdir -p "$MIG/state"
    case ${3:-check} in
    start)
        sudo -v
        if sudo tmux has-session -t "$ss" 2>/dev/null; then
            sudo tmux capture-pane -p -t "$ss" | grep -q '^read test ended' || die "$ss already runs: '$0 readtest $row' checks, '$0 readtest $row stop' stops it"
            sudo tmux kill-session -t "$ss"
        fi
        cmd=""; : >"$st.disks"
        for nn in ${ROW[$row]}; do
            d=$(link_of "$nn")
            [[ -n $d ]] || { echo "$nn: missing, not read"; continue; }
            b=$(basename "$(readlink -f "$d")")
            echo "$nn $b $(awk '{ print $3 }' "$SYS/block/$b/stat")" >>"$st.disks"
            cmd+="dd if=/dev/$b of=/dev/null bs=4M iflag=direct status=none & "
        done
        [[ -s $st.disks ]] || die "no disk of row $row is present"
        date +%s >"$st.start"; rm -f "$st.last"
        kernel_mark "migrate-row readtest $row start"
        sudo tmux new-session -d -s "$ss" "${cmd}wait; echo 'read test ended; press enter'; read"
        echo "row $row: $(wc -l <"$st.disks") disks being read in root's tmux session $ss"
        echo "check: $0 readtest $row [SECONDS]   stop: $0 readtest $row stop"
        ;;
    check)
        [[ -f $st.disks ]] || die "no read test of row $row was started"
        every=${4:-0}
        [[ $every =~ ^[0-9]+$ ]] || die "check takes seconds between checks"
        while true; do
            t0=$(cat "$st.start")
            if ! sudo tmux has-session -t "$ss" 2>/dev/null; then state=stopped
            elif sudo tmux capture-pane -p -t "$ss" | grep -q '^read test ended'; then state="ended (every disk read to its end, or the reads failed)"
            else state=running; fi
            # A disk the system lost has no counters any more: its last figures stand.
            declare -A s1=() last=()
            [[ -f $st.last ]] && while read -r nn v; do last[$nn]=$v; done <"$st.last"
            while read -r nn b s0; do s1[$nn]=$(awk '{ print $3 }' "$SYS/block/$b/stat" 2>/dev/null || echo "${last[$nn]:-$s0}"); done <"$st.disks"
            sleep 5
            now=$(date +%s)
            echo "$(date '+%T') read test row $row: $state, $(((now - t0) / 60)) min since $(date -d "@$t0" '+%F %T')"
            : >"$st.last"
            while read -r nn b s0; do
                s2=$(awk '{ print $3 }' "$SYS/block/$b/stat" 2>/dev/null || echo "${s1[$nn]}")
                echo "$nn $s2" >>"$st.last"
                printf '    %s %-5s %5d MB/s now, %5d MB/s average, %7d GB read%s\n' "$nn" "$b" $(((s2 - s1[$nn]) * 512 / 5000000)) \
                    $(((s2 - s0) * 512 / (now - t0) / 1000000)) $(((s2 - s0) * 512 / 1000000000)) \
                    "$([[ -e $SYS/block/$b ]] || echo ', GONE: the system lost this disk')"
            done <"$st.disks"
            since=$(mktemp)
            kernel_log | sed -n "/migrate-row readtest $row start/,\$p" >"$since"
            echo "links since the start:"
            # Only this box: the plan's other disks may be unplugged for the test.
            MIG_DMESG=$since link_report | grep -v '^    missing from the system' | sed 's/since boot/since the start/' || true
            rm -f "$since"
            ((every > 0)) || break
            sleep "$every"
        done
        ;;
    stop)
        if sudo tmux kill-session -t "$ss" 2>/dev/null; then echo "read test of row $row stopped"; else echo "no read test of row $row runs"; fi
        ;;
    *) die "readtest ROW [start | check [SECONDS] | stop]" ;;
    esac
    ;;
extra)
    prepare
    LOG=$MIG/heal.log
    if sudo tmux has-session -t mig-33 2>/dev/null; then
        worker_ended mig-33 || { echo "disk 33 is already being copied (sudo tmux attach -t mig-33)"; exit 0; }
        sudo tmux kill-session -t mig-33
    fi
    pool_mount >/dev/null || die "no pool"
    part=${2:-$(for d in $(lsblk -dnpo NAME,TRAN | awk '$2 == "usb" { print $1 }'); do
        lsblk -bnrpo NAME,FSTYPE,SIZE "$d" | awk -v fs="$SRC_FS" '$2 == fs && $3 > 1e13 { print $1 }'; done)}
    [[ -n $part && $(wc -l <<<"$part") == 1 ]] || die "want one $SRC_FS partition over 10 TB on a USB disk, found: $(echo ${part:-none})"
    [[ $(fstype_of "$part") == "$SRC_FS" ]] || die "$part is not $SRC_FS"
    src=$MIG/mnt/src-33
    mount_at 33 "$part" "$src" ro
    mapfile -t vx < <(volume_excludes)
    inhibit=""; sudo systemd-inhibit --what=sleep:idle --who=migrate-row --why=probe true 2>/dev/null && inhibit="systemd-inhibit --what=sleep:idle --who=migrate-row --why='disk 33 copying'"
    # rsync goes on as it lists (no --no-inc-recursive: listing millions of small files first takes
    # days on this disk); exit 23/24 lists in the log what could not be read.
    sudo tmux new-session -d -s mig-33 "{ $inhibit rsync -aH ${vx[*]@Q} --ignore-existing --info=progress2,stats1 '$src/' '$POOL/'; echo \"rsync finished with code \$?\"; } 2>&1 | tee -a '$MIG/33.log'; echo; echo 'worker ended; press enter'; read"
    log "disk 33: copying $part to the pool in tmux session mig-33"
    echo "disk 33 ($part) is being copied in root's tmux session mig-33; log $MIG/33.log"
    ;;
status)
    for row in A B C D; do
        n=0; done_n=0
        for nn in ${ROW[$row]}; do n=$((n + 1)); grep -s "^$nn -> " "$MIG/state/placement.txt" | tail -n 1 | grep -qv ' undone ' && done_n=$((done_n + 1)); done
        # A live copy holds a claim whose pid exists.
        run=0; ended=0
        for ss in $(sudo tmux ls -F '#S' 2>/dev/null | grep "^mig-$row-" || true); do
            if worker_ended "$ss"; then ended=$((ended + 1)); else run=$((run + 1)); fi
        done
        busy=""
        for nn in ${ROW[$row]}; do
            p=$(cat "$MIG/state/claim-$nn/pid" 2>/dev/null || true)
            [[ -n $p && -d /proc/$p ]] && busy+="$nn "
        done
        printf 'row %s: %d of %d disks copied; workers: %d running, %d ended; busy now: %s\n' "$row" "$done_n" "$n" \
            "$run" "$ended" "${busy:-none}"
        [[ -f $MIG/$row.log ]] && grep -E "^[0-9]{4}-" "$MIG/$row.log" | tail -n 1 | sed "s/^/    /"
    done
    if sudo tmux has-session -t mig-33 2>/dev/null; then
        printf 'disk 33 (USB): %s\n' "$(worker_ended mig-33 && echo 'copy ended' || echo 'copying')"
        sudo tmux capture-pane -p -t mig-33 | tr '\r' '\n' | grep -v -e 'file has vanished' -e 'worker ended' -e '^ *$' | tail -n 1 | sed 's/^/    /' || true
    fi
    [[ -f $MIG/state/placement.txt ]] && { echo "placement:"; sed 's/^/    /' "$MIG/state/placement.txt"; }
    echo "pool:"
    if findmnt -n "$POOL" >/dev/null; then
        printf '    %s: %s free, branches %s, new files by %s\n' "$POOL" "$(df -h --output=avail "$POOL" | tail -n 1 | tr -d ' ')" \
            "$(pool_branches)" "$(sudo getfattr -n user.mergerfs.category.create --only-values "$POOL/.mergerfs" 2>/dev/null || echo '?')"
    else
        echo "    not mounted"
    fi
    bad=$(cd "$MIG/state" 2>/dev/null && ls ./*.bad 2>/dev/null | sed 's|^\./||; s|\.bad$||' | tr '\n' ' ' || true)
    [[ -z $bad ]] || echo "bad (out of the pool, 'good NN' puts one back): $bad"
    [[ ! -f $MIG/state/stop ]] || echo "STOPPED: $(cat "$MIG/state/stop")"
    if [[ -f $MIG/state/rest ]]; then echo "rest: the rows take turns, $(cat "$MIG/state/rest") minutes each ('rest off' ends it)"; fi
    for r in A B C D 33; do
        if [[ -f $MIG/state/paused-$r ]]; then echo "paused: row $r since $(cat "$MIG/state/paused-$r") ('resume $r')"; fi
    done
    echo "links:"
    link_report
    echo "mounted:"
    findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep "$MIG/mnt" | sed 's/^/    /' || true
    ;;
rescan)
    # rescan [NN...]: ask the SATA port of each disk (default: every disk of the plan the system
    # has lost) to look for its disk again, as after a reseat or a power fix; then wait until each
    # answers a read. Name the disabled ones too: they keep their /dev name.
    shift
    prepare
    LOG=$MIG/heal.log
    list=${*:-$(missing_disks)}
    [[ -n $list ]] || { echo "every disk of the plan is present"; exit 0; }
    declare -A scanned
    for nn in $list; do
        [[ $nn =~ ^[0-3][0-9]$ ]] || die "$nn is not a disk name"
        hs=$(hosts_of "$nn") || { echo "$nn: no free SATA port found in its box (domain in $PLAN)"; continue; }
        log "rescan: disk $nn, ports $(echo $hs)"
        for h in $hs; do
            [[ -n ${scanned[$h]:-} ]] && continue
            scanned[$h]=1
            echo '- - -' | sudo tee "$SYS/class/scsi_host/$h/scan" >/dev/null || true
        done
    done
    sleep 5
    for ((i = 0; i < ${MIG_RESCAN_WAIT:-60}; i += 5)); do
        left=""
        for nn in $list; do disk_answers "$nn" || left+="$nn "; done
        [[ -z $left ]] && break
        sleep 5
    done
    for nn in $list; do
        if disk_answers "$nn"; then echo "$nn: answers again ($(readlink -f "$(link_of "$nn")")); a pool bay goes back with 'good $nn', a source is copied by its row's worker"
        else echo "$nn: does not answer (status shows why; a reboot is the next step)"; fi
    done
    ;;
heal)
    prepare
    LOG=$MIG/heal.log
    pool_mount >/dev/null || die "no pool"
    if heal_pool; then echo "pool now: $(pool_branches)"; else echo "every branch takes a write: $(pool_branches)"; fi
    ;;
bad)
    shift
    [[ $# -gt 0 ]] || die "bad needs disk names, e.g. bad 15"
    prepare
    LOG=$MIG/heal.log
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ ]] || die "$nn is not a disk name"
        mark_bad "$nn"
        log "disk $nn marked bad: out of the pool until 'good $nn'"
    done
    findmnt -n "$POOL" >/dev/null && echo "pool now: $(pool_branches)"
    ;;
aside)
    # aside NN "YYYY-MM-DD HH:MM" ["YYYY-MM-DD HH:MM"]: by hand, what a worker does when NN fails a
    # write (check_writes), for a failure no worker saw: the files changed on hd-NN since then (and
    # not after the second time, for an old failure while copies go on) go aside on it, copied again
    # by the next pass, and sources verified since then are copied and verified again.
    [[ ($# == 3 || $# == 4) && $2 =~ ^[0-3][0-9]$ ]] || die "aside needs a disk and a time, e.g. aside 15 \"2026-10-16 21:33\" [\"2026-10-16 22:10\"]"
    since=$(date -d "$3" '+%F %T') || die "not a time: $3"
    upto=""; [[ -z ${4:-} ]] || upto=$(date -d "$4" '+%F %T') || die "not a time: $4"
    prepare
    LOG=$MIG/heal.log
    mount_branch "$2"
    formatted=$(uncopy "$2" "$since")
    [[ -z $formatted ]] || die "$(echo $formatted) verified and formatted since $since with hd-$2 as a branch: nothing moved; their files may exist only on hd-$2"
    log "aside: hd-$2: $(aside_since "$2" "$since" "$upto") files changed since $since${upto:+ and not after $upto} moved aside on it; the next pass copies them again"
    ;;
good)
    shift
    [[ $# -gt 0 ]] || die "good needs disk names, e.g. good 15"
    prepare
    LOG=$MIG/heal.log
    pool_mount >/dev/null || die "no pool"
    for nn in "$@"; do
        [[ $nn =~ ^[0-3][0-9]$ ]] || die "$nn is not a disk name"
        pool_add "$nn"
        rm -f "$MIG/state/$nn.bad"
    done
    ;;
*)
    echo "usage: $0 {plan ROW | start ROW [N] | run ROW | attach ROW [N] | status | stats [S] | pool | rescan [NN...] | heal | bad NN... | good NN... | aside NN TIME [TIME] | recheck NN... | finish | add NN... | erase NN... | defer NN... | pause ROW... | resume ROW... | rest MIN|off | policy [NAME] | readtest ROW [start|check [S]|stop] | extra [PART] | mergerfs}   ROW = A, B, C or D" >&2
    exit 2
    ;;
esac
