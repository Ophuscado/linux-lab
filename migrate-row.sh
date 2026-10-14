#!/usr/bin/env bash
# shellcheck disable=SC2024
# (the log file belongs to the user; sudo is for the command only)
# migrate-row.sh: move one row of eight 18 TB disks from HFS+ to XFS, disk by disk, until
# the row's parity disk (24, 00, 08, 16) is empty.
#
# The plan, in plain words. A row is eight bays:
#
#   A  24 25 26 27 28 29 30 31   parity 24
#   B  00 01 02 03 04 05 06 07   parity 00
#   C  08 09 10 11 12 13 14 15   parity 08
#   D  16 17 18 19 20 21 22 23   parity 16
#
# Every disk still on HFS+ with more than 10 GB on it is a source (an emptier one holds
# only HFS+ metadata and is just formatted when needed). Every disk this script has formatted to XFS and
# not yet filled is a target; the row's parity disk is never a target. Each round takes
# the SMALLEST remaining source (the parity disk last, since emptying it frees no bay) and
# copies it whole onto the target with the most free space that fits it, checks the copy, and only then may the source be formatted, which
# makes it the next target. Small disks go first, so free disks appear early; the two
# disks that are full to the last gigabyte go last, onto a fresh disk. Where each disk's
# content landed is written to ~/migrate/state/placement.txt; a disk's data is never
# split.
#
# Workers: "start A 2" runs two copies of row A at once (four disks busy); "start A" one
# (two disks busy, six free to spin down). Rows are independent; run them in parallel.
#
# What one copy "nn>mm" does, and what stops it:
#   1. mm is formatted: one GPT partition, XFS, label HD_mm. The one destructive command.
#      It happens on its own only for a disk this script emptied by a verified copy or
#      found under 10 GB; any other disk needs you to type "erase mm" at the prompt,
#      after seeing what it holds. A row has seven bays for data and eight disks; when
#      all eight hold data, the old parity disk (last bay) is the one that asks.
#   2. nn is mounted read-only, mm read-write, and rsync copies everything with owners,
#      times, permissions and extended attributes (resource forks do not exist on Linux
#      and are not copied). Up to three passes until nothing is left.
#   3. Verification: every file is read back on both sides and compared by checksum
#      (VERIFY=quick compares only size and time; faster, weaker). Any difference stops
#      the worker; the source is untouched and mm is set aside as "dirty".
#   4. nn is marked "copied to mm, verified"; it may now be formatted.
# A worker logs to ~/migrate/<row>.log; state lives in ~/migrate/state/. A stopped or
# crashed worker is restarted with the same command and continues.
#
#   migrate-row.sh plan A           what the row holds and what the first round would do
#   migrate-row.sh start A [N]      run N workers (default 1) in tmux sessions mig-A-1..N
#   migrate-row.sh run A            one worker in this terminal
#   migrate-row.sh status           every row: disks copied, workers, placement, mounts
#   migrate-row.sh attach A [N]     watch a worker (Ctrl-b d to leave it running)
#
# Needs ~/disk-plan.csv from disk-inventory.sh with every disk named, and the packages
# xfsprogs rsync tmux parted (installed on the first run).
#
# Test hooks: MIG_PLAN, MIG_HOME, MIG_SRC_FS (filesystem type of the sources, hfsplus),
# MIG_EMPTY_LIMIT (bytes).

set -euo pipefail

PLAN=${MIG_PLAN:-$HOME/disk-plan.csv}
MIG=${MIG_HOME:-$HOME/migrate}
SRC_FS=${MIG_SRC_FS:-hfsplus}
VERIFY=${VERIFY:-full}
EMPTY_LIMIT=${MIG_EMPTY_LIMIT:-10000000000} # bytes; under 10 GB is HFS+ metadata, not data

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
        mount_at "$nn" "$part" "$m" ro
        echo "xfs $(used_at "$m") $(avail_at "$m")"
        sudo umount "$m"
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
    rm -f "$MIG/state/$mm.copied" "$MIG/state/$mm.dirty" "$MIG/state/$mm.filled"
    log "$mm: formatted"
}

# $1 source name, $2 target name.
copy_disk() {
    local nn=$1 mm=$2 src dst s d pass rc
    src=$MIG/mnt/src-$nn
    dst=$MIG/mnt/hd-$mm
    s=$(part_of "$(disk_of "$nn")") || exit 1
    d=$(part_of "$(disk_of "$mm")") || exit 1
    [[ -b $s && -b $d ]] || die "$nn>$mm: partitions not found"
    [[ $(fstype_of "$s") == "$SRC_FS" ]] || die "$nn is not $SRC_FS any more"
    [[ $(fstype_of "$d") == xfs && $(label_of "$d") == "HD_$mm" ]] || die "$mm is not the XFS disk HD_$mm"
    mount_at "$nn" "$s" "$src" ro
    sudo blockdev --setrw "$d"
    mount_at "$mm" "$d" "$dst" rw,noatime
    touch "$MIG/state/$mm.dirty" # until verified, mm holds a copy in progress
    log "$nn>$mm: copying $(used_at "$src") bytes from $s to $d"
    for pass in 1 2 3; do
        rc=0
        sudo rsync -aHAX --info=progress2,stats1 --no-inc-recursive "$src/" "$dst/" >>"$LOG" 2>&1 || rc=$?
        # 23/24: some files could not be read or vanished; those are listed in the log.
        log "$nn>$mm: rsync pass $pass finished with code $rc"
        [[ $rc == 0 ]] && break
        [[ $rc == 23 || $rc == 24 ]] || die "$nn>$mm: rsync failed (code $rc); see $LOG. $mm is set aside as dirty."
    done
    [[ $rc == 0 ]] || die "$nn>$mm: files could not be copied after three passes; see $LOG. $mm is set aside as dirty."
    sync
    log "$nn>$mm: copy done, $(used_at "$dst") bytes on $mm"
}

# $1 source, $2 target: read everything back and compare.
verify_disk() {
    local nn=$1 mm=$2 src dst diff opts nsrc ndst
    src=$MIG/mnt/src-$nn
    dst=$MIG/mnt/hd-$mm
    if [[ $VERIFY == quick ]]; then
        opts=(-rln --times --size-only)
        log "$nn>$mm: verifying by size and time"
    else
        opts=(-rlnc)
        log "$nn>$mm: verifying every file by checksum (reads both disks in full)"
    fi
    diff=$(sudo rsync "${opts[@]}" --delete --out-format='%n' "$src/" "$dst/" 2>&1 | grep -v '^\./$' || true)
    if [[ -n $diff ]]; then
        printf '%s\n' "$diff" >>"$MIG/state/$nn.differences"
        die "$nn>$mm: $(wc -l <<<"$diff") differences; see $MIG/state/$nn.differences. Source untouched, $mm dirty."
    fi
    nsrc=$(sudo find "$src" -xdev -type f | wc -l)
    ndst=$(sudo find "$dst" -xdev -type f | wc -l)
    [[ $nsrc == "$ndst" ]] || die "$nn>$mm: $nsrc files on $nn, $ndst on $mm. Source untouched, $mm dirty."
    sudo umount "$src"
    sudo umount "$dst"
    rm -f "$MIG/state/$mm.dirty"
    touch "$MIG/state/$mm.filled"
    echo "copied to $mm, $nsrc files, verified $VERIFY $(date '+%F %T')" >"$MIG/state/$nn.copied"
    echo "$nn -> $mm  $nsrc files  $(date '+%F %T')" >>"$MIG/state/placement.txt"
    log "$nn>$mm: verified, $nsrc files. $nn may now be formatted."
}

# ---- the scheduler ----------------------------------------------------------------------

# Claims keep two workers off the same disk; a claim is a directory, made atomically.
claim() { mkdir "$MIG/state/claim-$1" 2>/dev/null; }
release() { rmdir "$MIG/state/claim-$1" 2>/dev/null || true; }
claimed() { [[ -d $MIG/state/claim-$1 ]]; }

# Prints "nn USED" for every HFS+ disk of row $1 not yet copied and not claimed, smallest
# first, the parity disk last.
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
        # The parity disk frees no bay when copied, so it goes last whatever its size.
        [[ $nn == "${PARITY[$1]}" ]] && echo "$nn ${st#src } last" || echo "$nn ${st#src } first"
    done | sort -k3,3 -k2,2n | cut -d' ' -f1,2
}

# Prints "mm AVAIL" for every formatted, unfilled, unclaimed XFS disk of row $1 (never the
# parity disk), most free space first.
targets_of() {
    local mm st
    for mm in ${ROW[$1]}; do
        [[ $mm == "${PARITY[$1]}" ]] && continue
        [[ -f $MIG/state/$mm.filled || -f $MIG/state/$mm.dirty ]] && continue
        claimed "$mm" && continue
        st=$(disk_state "$mm")
        [[ $st == xfs* ]] && echo "$mm ${st##* }"
    done | sort -k2,2nr
}

# Prints a disk of row $1 that may be formatted now: one this script emptied by a verified
# copy and has not reformatted; else, before the first round, the row's last bay (the old
# parity disk, which asks for confirmation); else nothing.
formattable_of() {
    local nn
    for nn in ${ROW[$1]}; do
        [[ $nn == "${PARITY[$1]}" ]] && continue
        claimed "$nn" && continue
        if [[ -f $MIG/state/$nn.copied ]] && [[ $(disk_state "$nn") == src* ]]; then
            echo "$nn"
            return
        fi
    done
    [[ -f $MIG/state/row-$1.started ]] || echo "${ROW[$1]##* }"
}

# One worker: rounds until no source is left.
run_row() {
    local row=$1 src used tgt avail need line mm
    while true; do
        line=$(sources_of "$row" | head -n 1)
        if [[ -z $line ]]; then
            log "row $row: no source left for this worker"
            break
        fi
        read -r src used <<<"$line"
        claim "$src" || { sleep 60; continue; }
        need=$((used + used / 1000 + 1000000000)) # 0.1 % and 1 GB of slack
        tgt=""
        while read -r mm avail; do
            [[ -n $mm && $avail -ge $need ]] && { tgt=$mm; break; }
        done < <(targets_of "$row")
        if [[ -z $tgt ]]; then
            tgt=$(formattable_of "$row")
            if [[ -z $tgt ]]; then
                release "$src"
                if [[ -n $(ls -d "$MIG"/state/claim-* 2>/dev/null) ]]; then
                    log "row $row: nothing fits $src ($used bytes) yet; waiting for other workers"
                    sleep 300
                    continue
                fi
                die "row $row: nothing fits $src ($used bytes) and nothing can be formatted. See placement.txt; free a disk by hand or split this one."
            fi
            claim "$tgt" || { release "$src"; sleep 60; continue; }
            format_target "$tgt"
            touch "$MIG/state/row-$row.started"
        else
            claim "$tgt" || { release "$src"; sleep 60; continue; }
        fi
        log "round: $src ($used bytes) -> $tgt"
        copy_disk "$src" "$tgt"
        verify_disk "$src" "$tgt"
        release "$src"
        release "$tgt"
    done
    # The parity disk: once its content is copied it holds nothing we need.
    if [[ -f $MIG/state/${PARITY[$row]}.copied && $(disk_state "${PARITY[$row]}") == src* ]] && claim "${PARITY[$row]}"; then
        log "row $row: formatting parity disk ${PARITY[$row]}"
        format_target "${PARITY[$row]}"
        release "${PARITY[$row]}"
    fi
    log "row $row: worker finished"
}

# ---- front ------------------------------------------------------------------------------

need_row() { [[ -n ${1:-} && -n ${ROW[$1]:-} ]] || die "row must be A, B, C or D"; }

prepare() {
    [[ -r $PLAN ]] || die "no $PLAN; run disk-inventory.sh first"
    ! grep -q ',?$' "$PLAN" || die "$PLAN still has unnamed disks"
    [[ $(tail -n +2 "$PLAN" | cut -d, -f14 | sort | uniq -d | wc -l) == 0 ]] || die "$PLAN names a disk twice; run disk-inventory.sh again"
    [[ $(tail -n +2 "$PLAN" | wc -l) == 32 ]] || echo "WARN: $PLAN lists $(tail -n +2 "$PLAN" | wc -l) disks, not 32"
    mkdir -p "$MIG/state" "$MIG/mnt"
    for t in mkfs.xfs rsync parted tmux; do
        command -v "$t" >/dev/null || sudo dnf install -y xfsprogs rsync parted tmux
    done
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
        [[ -f $MIG/state/$nn.dirty ]] && printf '  DIRTY: holds a failed copy'
        echo
    done
    nsets=$(sources_of "$2" | wc -l)
    ((nsets <= 7)) || echo "  WARN: $nsets disks hold data and the row has 7 bays for it: the last bay (${ROW[$2]##* }) will be erased without a copy, after you confirm"
    echo "  copies, smallest source first:"
    sources_of "$2" | awk '{ printf "    %s (%.2f TB)\n", $1, $2 / 1e12 }'
    echo "  targets ready now: $(targets_of "$2" | awk '{ printf "%s (%.2f TB free) ", $1, $2 / 1e12 }')"
    echo "  formatted without asking when needed (under $((EMPTY_LIMIT / 1000000)) MB): $(for nn in ${ROW[$2]}; do [[ -f $MIG/state/$nn.copied ]] && grep -q '^empty' "$MIG/state/$nn.copied" && printf '%s ' "$nn"; done)"
    f=$(formattable_of "$2")
    if [[ -n $f && -f $MIG/state/$f.copied ]]; then
        echo "  first disk to be formatted: $f (empty, without asking)"
    elif [[ -n $f ]]; then
        echo "  first disk to be formatted: $f (holds data that will NOT be copied; asks for 'erase $f')"
    else
        echo "  first disk to be formatted: none needed now"
    fi
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
        if tmux has-session -t "mig-$2-$i" 2>/dev/null; then
            echo "worker mig-$2-$i is already running"
            continue
        fi
        tmux new-session -d -s "mig-$2-$i" "VERIFY=$VERIFY '$0' run $2; echo; echo 'worker ended; press enter'; read"
        echo "row $2 worker $i started in tmux session mig-$2-$i"
        [[ $i == 1 && $n -gt 1 ]] && sleep 20 # let the first one take the confirmation prompt
    done
    echo "Watch: $0 attach $2 [N]; progress: $0 status"
    ;;
attach) tmux attach -t "mig-${2:-}-${3:-1}" ;;
status)
    for row in A B C D; do
        n=0; done_n=0
        for nn in ${ROW[$row]}; do n=$((n + 1)); [[ -f $MIG/state/$nn.copied ]] && done_n=$((done_n + 1)); done
        printf 'row %s: %d of %d disks copied; workers running: %s\n' "$row" "$done_n" "$n" \
            "$(tmux ls 2>/dev/null | grep -c "^mig-$row-" || true)"
        [[ -f $MIG/$row.log ]] && tail -n 1 "$MIG/$row.log" | sed 's/^/    /'
    done
    [[ -f $MIG/state/placement.txt ]] && { echo "placement:"; sed 's/^/    /' "$MIG/state/placement.txt"; }
    echo "mounted:"
    findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep "$MIG/mnt" | sed 's/^/    /' || true
    ;;
*)
    echo "usage: $0 {plan ROW | start ROW [N] | run ROW | attach ROW [N] | status}   ROW = A, B, C or D" >&2
    exit 2
    ;;
esac
