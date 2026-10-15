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
#      info, quarantine and Spotlight metadata, which the driver cannot read). A file that already exists in the pool under
#      the same path is never overwritten (--ignore-existing); verification then reports it.
#   3. Verification: every file of the source is looked up in the pool and compared by size
#      and time (VERIFY=full reads both back and compares checksums; twice the time). Any
#      difference stops the worker; the source is untouched.
#   4. The source is marked "copied, verified"; it may now be formatted and join the pool.
# Parent folders with the same name on several sources merge into one folder in the pool,
# which is what a library spread over disks looks like afterwards.
# A disk on a flaky link ("defer 28") is copied after everything else in its row.
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
#   migrate-row.sh recheck NN ...   after a disk or box fault during copies: files of these
#                                   sources that exist in the pool are compared by checksum
#                                   and a copy that differs, or that exists on two branches,
#                                   is moved aside on its disk (.migrate-aside/), so the next
#                                   pass rewrites it instead of skipping it. Nothing deleted.
#   migrate-row.sh finish           when every worker is done: checks all 32 disks are XFS,
#                                   unmounts the migration pool and mounts; next is
#                                   snapraid-setup.sh install, mount, first
#   migrate-row.sh add 23 ...       format these bays now and add them to the pool (only
#                                   disks already copied, marked "erase" or found empty;
#                                   otherwise a worker does it when the pool needs room)
#   migrate-row.sh mergerfs        build and install mergerfs 2.42.0 (once; Fedora has no package)
#   migrate-row.sh erase 07 15 ...  mark disks whose content is not needed: formatted
#                                   without a copy and without asking
#
# Needs ~/disk-plan.csv from disk-inventory.sh with every disk named, and the packages
# xfsprogs rsync tmux parted attr (installed on the first run) and mergerfs ("mergerfs" command).
#
# Test hooks: MIG_PLAN, MIG_HOME, MIG_SRC_FS (filesystem type of the sources, hfsplus),
# MIG_EMPTY_LIMIT (bytes), MIG_MINFREE (mergerfs minfreespace), MIG_MERGERFS (binary),
# MIG_WAIT (seconds between looks at a full pool).

set -euo pipefail

PLAN=${MIG_PLAN:-$HOME/disk-plan.csv}
MIG=${MIG_HOME:-$HOME/migrate}
SRC_FS=${MIG_SRC_FS:-hfsplus}
VERIFY=${VERIFY:-quick}
EMPTY_LIMIT=${MIG_EMPTY_LIMIT:-10000000000} # bytes; under 10 GB is HFS+ metadata, not data
MINFREE=${MIG_MINFREE:-4G} # mergerfs stops placing new files on a branch below this
# Where a new file goes: pfrd picks a branch at random, weighted by free space, so parallel
# streams land on different disks (mfs would send them all to the emptiest one at a time).
CREATE=${MIG_CREATE:-pfrd}
MERGERFS=${MIG_MERGERFS:-mergerfs}
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
disk_of() {
    local d
    d=$(awk -F, -v n="$1" '$14 == n { print $4 }' "$PLAN")
    [[ -n $d ]] || die "disk $1 is not in $PLAN"
    [[ $(wc -l <<<"$d") == 1 ]] || die "disk $1 appears more than once in $PLAN; run disk-inventory.sh again"
    [[ -b $d ]] || die "disk $1 ($d) is not present"
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
used_at() { df -B1 --output=used "$1" | tail -n 1 | tr -d ' '; }
avail_at() { df -B1 --output=avail "$1" | tail -n 1 | tr -d ' '; }

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
            # Type and label only: no mount, so 32 cold disks do not each spin up for a look.
            part=$(part_of "$(disk_of "$mm")") || exit 1
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
    local nn=$2 src dst s pass rc
    src=$MIG/mnt/src-$nn
    dst=$POOL
    s=$(part_of "$(disk_of "$nn")") || exit 1
    [[ $(fstype_of "$s") == "$SRC_FS" ]] || die "$nn is not $SRC_FS any more"
    findmnt -n "$dst" >/dev/null || die "pool is not mounted"
    mount_at "$nn" "$s" "$src" ro
    log "$nn>pool: copying $(used_at "$src") bytes from $s; pool has $(pool_avail) free"
    for pass in 1 2 3; do
        rc=0
        # Extended attributes: all but system.* and the Apple ones (osx.*: Finder info,
        # quarantine, provenance, Spotlight metadata), which the hfsplus driver lists under
        # truncated names it cannot read back; security.* (SELinux labels) on the XFS side
        # are left alone, not deleted.
        sudo rsync -aHAX --filter='-x system.*' --filter='-x osx.*' --filter='-xr security.*' \
            --ignore-existing --info=progress2,stats1 --no-inc-recursive "$src/" "$dst/" >>"$LOG" 2>&1 || rc=$?
        # 23/24: some files could not be read or vanished; those are listed in the log.
        log "$nn>pool: rsync pass $pass finished with code $rc"
        [[ $rc == 0 ]] && break
        [[ $rc == 23 || $rc == 24 ]] || die "$nn>pool: rsync failed (code $rc); see $LOG. Source untouched."
    done
    [[ $rc == 0 ]] || die "$nn>pool: files could not be copied after three passes; see $LOG. Source untouched."
    sync
    log "$nn>pool: copy done; pool has $(pool_avail) free"
}

# $1 row, $2 source: read every file of the source back from the pool and compare.
verify_disk() {
    local row=$1 nn=$2 src dst diff opts
    src=$MIG/mnt/src-$nn
    dst=$POOL
    if [[ $VERIFY == quick ]]; then
        opts=(-rln --times --size-only)
        log "$nn>pool: verifying by size and time"
    else
        opts=(-rlnc)
        log "$nn>pool: verifying every file by checksum (reads the source and its copy in full)"
    fi
    # No --delete: the pool also holds the other sources' files.
    diff=$(sudo rsync "${opts[@]}" --out-format='%n' "$src/" "$dst/" 2>&1 | grep -v '^\./$' || true)
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
            claimed "$nn" && continue
            if [[ -f $MIG/state/$nn.copied ]] && [[ $(disk_state "$nn") == src* ]]; then
                echo "$nn"
                return
            fi
        done
    done
    [[ -f $MIG/state/row-$1.started ]] || echo "${ROW[$1]##* }"
}

# One worker: rounds until no source is left.
run_row() {
    local row=$1 src used tgt need line
    pool_mount >/dev/null 2>&1 || true
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
    prepare
    LOG=$MIG/recheck.log
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-' || die "workers still run; sudo tmux kill-server first"
    pool_mount >/dev/null || die "no pool"
    aside=0
    # 1. The same path on two branches: the copy on the branch that comes first in the pool
    #    hides the other. Both are kept; the first one goes aside, the next pass compares.
    log "recheck: looking for paths present on two branches"
    seen=$MIG/state/recheck.paths; : >"$seen"; prev=""; prevbr=""
    for br in $(pool_branches); do
        sudo find "$MIG/mnt/hd-$br" -xdev -type f ! -path '*/.migrate-aside/*' -printf "$br\t%P\n"
    done | sort -t$'\t' -k2,2 -s >"$seen"
    while IFS=$'\t' read -r br path; do
        [[ $path == "$prev" ]] || { prev=$path; prevbr=$br; continue; }
        # second branch with the same path: move the earlier one (lower in branch order) aside
        to="$MIG/mnt/hd-$prevbr/.migrate-aside/dup/$path"
        sudo mkdir -p "$(dirname "$to")"; sudo mv "$MIG/mnt/hd-$prevbr/$path" "$to"
        log "recheck: '$path' on $prevbr and $br; the $prevbr copy moved aside"
        aside=$((aside + 1)); prev=$path; prevbr=$br
    done < <(cat "$seen"; echo)
    # 2. Checksum of every file of each source that has a copy in the pool.
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
        done < <(sudo rsync -rlc --existing --dry-run --out-format='%n' --filter='-x *' "$src/" "$POOL/" 2>>"$LOG" | grep -v '^\./$' || true)
        sudo umount "$src"
    done
    log "recheck: $aside copies moved aside; the next copy pass rewrites them. Remove .migrate-aside folders when the row is verified."
    ;;
finish)
    prepare
    LOG=/dev/null
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-' && true || die "workers still run: $(sudo tmux ls | grep -o '^mig-[A-D]-[0-9]' | tr '\n' ' ')"
    left=""
    for row in A B C D; do for nn in ${ROW[$row]}; do [[ $(disk_state "$nn") == xfs* ]] || left+="$nn "; done; done
    [[ -z $left ]] || die "not XFS yet: $left(parity disks are formatted by their row's worker at its end; a source still HFS+ was not copied)"
    for row in A B C D; do for nn in ${ROW[$row]}; do [[ -f $MIG/state/$nn.differences ]] && echo "WARN: $nn.differences exists; a verify once failed, see it"; done; done
    sudo umount "$POOL" 2>/dev/null || true
    for m in $(findmnt -rn -o TARGET | grep "^$MIG/mnt/" | sort -r); do sudo umount "$m"; done
    echo "every disk is XFS; migration mounts released. Logs and placement stay in $MIG."
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
    log "row $2: worker start (VERIFY=$VERIFY)"
    run_row "$2"
    ;;
start)
    need_row "${2:-}"
    prepare
    n=${3:-1}
    [[ $n =~ ^[1-4]$ ]] || die "workers: 1 to 4"
    for i in $(seq 1 "$n"); do
        if sudo tmux has-session -t "mig-$2-$i" 2>/dev/null; then
            echo "worker mig-$2-$i is already running"
            continue
        fi
        # The worker holds a sleep inhibitor: a suspend would drop the tunnels mid-copy.
        inhibit=""; sudo systemd-inhibit --what=sleep:idle --who=migrate-row --why=probe true 2>/dev/null && inhibit="systemd-inhibit --what=sleep:idle --who=migrate-row --why='row $2 copying'"
        # The inner shell is root's: HOME and the hooks are passed on explicitly.
        sudo tmux new-session -d -s "mig-$2-$i" "HOME='$HOME' MIG_HOME='$MIG' MIG_PLAN='$PLAN' MIG_MERGERFS='$MERGERFS' MIG_SRC_FS='$SRC_FS' MIG_EMPTY_LIMIT='$EMPTY_LIMIT' MIG_MINFREE='$MINFREE' MIG_WAIT='$WAIT' VERIFY=$VERIFY $inhibit '$0' run $2; echo; echo 'worker ended; press enter'; read"
        echo "row $2 worker $i started in tmux session mig-$2-$i (root's tmux)"
        [[ $i == 1 && $n -gt 1 ]] && sleep 20 # let the first one take the confirmation prompt
    done
    echo "Watch: $0 attach $2 [N] (Ctrl-b d to leave); progress: $0 status"
    ;;
attach) sudo tmux attach -t "mig-${2:-}-${3:-1}" ;;
status)
    for row in A B C D; do
        n=0; done_n=0
        for nn in ${ROW[$row]}; do n=$((n + 1)); grep -qs "^$nn -> " "$MIG/state/placement.txt" && done_n=$((done_n + 1)); done
        printf 'row %s: %d of %d disks copied; workers running: %s\n' "$row" "$done_n" "$n" \
            "$(sudo tmux ls 2>/dev/null | grep -c "^mig-$row-" || true)"
        [[ -f $MIG/$row.log ]] && grep -E "^[0-9]{4}-" "$MIG/$row.log" | tail -n 1 | sed "s/^/    /"
    done
    [[ -f $MIG/state/placement.txt ]] && { echo "placement:"; sed 's/^/    /' "$MIG/state/placement.txt"; }
    echo "pool:"
    if findmnt -n "$POOL" >/dev/null; then
        printf '    %s: %s free, branches %s\n' "$POOL" "$(df -h --output=avail "$POOL" | tail -n 1 | tr -d ' ')" "$(pool_branches)"
    else
        echo "    not mounted"
    fi
    echo "mounted:"
    findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep "$MIG/mnt" | sed 's/^/    /' || true
    ;;
*)
    echo "usage: $0 {plan ROW | start ROW [N] | run ROW | attach ROW [N] | status | stats [S] | pool | recheck NN... | finish | add NN... | erase NN... | defer NN... | mergerfs}   ROW = A, B, C or D" >&2
    exit 2
    ;;
esac
