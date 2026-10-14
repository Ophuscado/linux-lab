#!/usr/bin/env bash
# shellcheck disable=SC2024
# (the log file belongs to the user; sudo is for the command only)
# migrate-row.sh: move one row of eight 18 TB disks from HFS+ to XFS, disk by disk, so
# that the row's first disk ends up empty for SnapRAID parity.
#
# The plan, in plain words. Each row has one empty disk (07, 15, 23, 31). The data of the
# disk next to it is copied there, checked, and only then is that disk formatted and used
# as the next target, and so on down the row, until the row's first disk (00, 08, 16, 24)
# is empty. Content moves one bay down; bay names (HD_nn) stay with the bays:
#
#   A  parity 24   30>31  29>30  28>29  27>28  26>27  25>26  24>25
#   B  parity 00   06>07  05>06  04>05  03>04  02>03  01>02  00>01
#   C  parity 08   14>15  13>14  12>13  11>12  10>11  09>10  08>09
#   D  parity 16   22>23  21>22  20>21  19>20  18>19  17>18  16>17
#
# One copy at a time per row, so two disks of a row are busy and the other six can spin
# down. Rows are independent: run the four in parallel, one tmux session each.
#
# What one step "nn>mm" does, and what stops it:
#   1. mm must be empty: either a disk already formatted by this script and holding
#      nothing, or an HFS+ volume with under 1 GB used (the old parity disks); anything
#      else is refused. A disk that still holds data this script has not verified as
#      copied is never formatted.
#   2. mm is formatted: one GPT partition, XFS, label HD_mm. The one destructive command;
#      the devices are shown and the name must be typed, except for a disk that this
#      script itself emptied in the previous step (its copy was verified).
#   3. nn is mounted read-only (HFS+), mm read-write, and rsync copies everything with
#      owners, times, permissions and extended attributes (resource forks do not exist on
#      Linux and are not copied). A second rsync pass is run until nothing is left.
#   4. Verification: every file is read back on both sides and compared by checksum
#      (VERIFY=quick compares only size and time; faster, weaker). Any difference stops
#      the row; the source is untouched.
#   5. nn is marked "copied to mm, verified"; the next step may format it. Symbolic
#      links keep their targets but get the copy's time, not the original's.
# Every step is logged to ~/migrate/<row>.log, state lives in ~/migrate/state/. A stopped
# or crashed run is restarted with the same command and continues where it was.
#
#   migrate-row.sh plan A         print the steps with the real devices, change nothing
#   migrate-row.sh start A        run row A in a tmux session named mig-A, detached
#   migrate-row.sh run A          run row A in this terminal
#   migrate-row.sh status         where each row is, and what is mounted
#   migrate-row.sh attach A       watch row A (Ctrl-b d to leave it running)
#
# Needs ~/disk-plan.csv from disk-inventory.sh with every disk named, and the packages
# xfsprogs rsync tmux parted (installed on the first run).
#
# Test hooks: MIG_PLAN, MIG_HOME, MIG_SRC_FS (filesystem type of the sources, hfsplus).

set -euo pipefail

PLAN=${MIG_PLAN:-$HOME/disk-plan.csv}
MIG=${MIG_HOME:-$HOME/migrate}
SRC_FS=${MIG_SRC_FS:-hfsplus}
VERIFY=${VERIFY:-full}
EMPTY_LIMIT=${MIG_EMPTY_LIMIT:-$((1000 * 1000 * 1000))} # 1 GB: more than this on a target is data

declare -A CHAIN=(
    [A]="30>31 29>30 28>29 27>28 26>27 25>26 24>25"
    [B]="06>07 05>06 04>05 03>04 02>03 01>02 00>01"
    [C]="14>15 13>14 12>13 11>12 10>11 09>10 08>09"
    [D]="22>23 21>22 20>21 19>20 18>19 17>18 16>17"
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

# Bytes used on a mounted filesystem.
used_at() { df -B1 --output=used "$1" | tail -n 1 | tr -d ' '; }

# ---- the steps --------------------------------------------------------------------------

# $1 target name. Refuses anything that is not empty.
check_target_empty() {
    local mm=$1 dev part fs m used
    dev=$(disk_of "$mm") || exit 1
    if [[ -f $MIG/state/$mm.copied ]]; then
        return 0 # this script emptied it: its data is verified on the next disk
    fi
    part=$(part_of "$dev") || exit 1
    fs=$(fstype_of "$part")
    m=$MIG/mnt/check-$mm
    case $fs in
    "$SRC_FS")
        mount_at "$mm" "$part" "$m" ro
        used=$(used_at "$m")
        sudo umount "$m"
        ((used < EMPTY_LIMIT)) || die "disk $mm ($dev) holds $((used / 1000000)) MB and was never copied by this script: not formatting it"
        ;;
    xfs)
        [[ $(label_of "$part") == "HD_$mm" ]] || die "disk $mm is XFS but not labelled HD_$mm; not touching it"
        mount_at "$mm" "$part" "$m" ro
        used=$(used_at "$m")
        sudo umount "$m"
        ((used < EMPTY_LIMIT)) || die "disk $mm is XFS and holds $((used / 1000000)) MB: not formatting it"
        ;;
    *) die "disk $mm ($dev) has filesystem '$fs': not formatting it" ;;
    esac
}

# $1 target name. The destructive step.
format_target() {
    local mm=$1 dev part answer
    dev=$(disk_of "$mm") || exit 1
    if [[ -f $MIG/state/$mm.formatted ]]; then
        log "$mm: already formatted"
        return 0
    fi
    check_target_empty "$mm"
    if [[ ! -f $MIG/state/$mm.copied ]]; then
        echo
        echo "About to ERASE disk $mm: $dev ($(readlink -f "$dev"), $(lsblk -dno MODEL,SIZE "$dev" | tr -s ' '))"
        echo "It holds $(fstype_of "$(part_of "$dev")") '$(label_of "$(part_of "$dev")")', under 1 GB used."
        read -r -p "Type $mm to erase it: " answer </dev/tty
        [[ $answer == "$mm" ]] || die "not confirmed; nothing changed"
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
    sudo mkfs.xfs -q -f -L "HD_$mm" "$part" >>"$LOG" 2>&1 || die "$mm: mkfs.xfs failed; see $LOG"
    sudo rm -f "$MIG/state/$mm.copied"
    touch "$MIG/state/$mm.formatted"
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
    log "$nn>$mm: copying $(du -sh "$src" 2>/dev/null | cut -f1 || echo '?') from $s to $d"
    for pass in 1 2 3; do
        rc=0
        sudo rsync -aHAX --info=progress2,stats1 --no-inc-recursive "$src/" "$dst/" >>"$LOG" 2>&1 || rc=$?
        # 23/24: some files could not be read or vanished; those are listed in the log.
        log "$nn>$mm: rsync pass $pass finished with code $rc"
        [[ $rc == 0 ]] && break
        [[ $rc == 23 || $rc == 24 ]] || die "$nn>$mm: rsync failed (code $rc); see $LOG"
    done
    [[ $rc == 0 ]] || die "$nn>$mm: files could not be copied after three passes; see $LOG"
    sync
    log "$nn>$mm: copy done, $(used_at "$dst") bytes on $mm"
}

# $1 source, $2 target: read everything back and compare.
verify_disk() {
    local nn=$1 mm=$2 src dst diff opts
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
        die "$nn>$mm: $(wc -l <<<"$diff") differences; see $MIG/state/$nn.differences. Source untouched."
    fi
    local nsrc ndst
    nsrc=$(sudo find "$src" -xdev -type f | wc -l)
    ndst=$(sudo find "$dst" -xdev -type f | wc -l)
    [[ $nsrc == "$ndst" ]] || die "$nn>$mm: $nsrc files on $nn, $ndst on $mm. Source untouched."
    sudo umount "$src"
    sudo umount "$dst"
    echo "copied to $mm, $nsrc files, verified $VERIFY $(date '+%F %T')" >"$MIG/state/$nn.copied"
    cp "$MIG/state/$nn.copied" "$MIG/state/step-$nn-$mm.done"
    log "$nn>$mm: verified, $nsrc files. $nn may now be formatted."
}

run_step() {
    local nn=${1%>*} mm=${1#*>}
    if [[ -f $MIG/state/step-$nn-$mm.done ]]; then
        log "$nn>$mm: done earlier ($(cat "$MIG/state/step-$nn-$mm.done"))"
        return 0
    fi
    format_target "$mm"
    copy_disk "$nn" "$mm"
    verify_disk "$nn" "$mm"
}

run_row() {
    local row=$1 step
    for step in ${CHAIN[$row]}; do
        run_step "$step"
    done
    log "row $row: all copies done. Parity disk ${PARITY[$row]} is empty; formatting it."
    format_target "${PARITY[$row]}"
    log "row $row: finished"
}

# ---- front ------------------------------------------------------------------------------

need_row() { [[ -n ${1:-} && -n ${CHAIN[$1]:-} ]] || die "row must be A, B, C or D"; }

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
    for step in ${CHAIN[$2]}; do
        nn=${step%>*}; mm=${step#*>}
        printf '  %s>%s  %s -> %s  %s\n' "$nn" "$mm" "$(readlink -f "$(disk_of "$nn")")" "$(readlink -f "$(disk_of "$mm")")" \
            "$([[ -f $MIG/state/step-$nn-$mm.done ]] && echo "done" || echo "pending")"
    done
    echo "  then format ${PARITY[$2]} ($(readlink -f "$(disk_of "${PARITY[$2]}")")) for parity"
    ;;
run)
    need_row "${2:-}"
    prepare
    LOG=$MIG/$2.log
    log "row $2: start (VERIFY=$VERIFY)"
    run_row "$2"
    ;;
start)
    need_row "${2:-}"
    prepare
    tmux has-session -t "mig-$2" 2>/dev/null && die "row $2 is already running: $0 attach $2"
    tmux new-session -d -s "mig-$2" "VERIFY=$VERIFY '$0' run $2; echo; echo 'row $2 ended; press enter'; read"
    echo "row $2 started in tmux session mig-$2. Watch: $0 attach $2; progress: $0 status"
    ;;
attach) tmux attach -t "mig-${2:-}" ;;
status)
    for row in A B C D; do
        n=0; done_n=0
        for step in ${CHAIN[$row]}; do n=$((n + 1)); [[ -f $MIG/state/step-${step%>*}-${step#*>}.done ]] && done_n=$((done_n + 1)); done
        printf 'row %s: %d of %d copies verified%s\n' "$row" "$done_n" "$n" \
            "$(tmux has-session -t "mig-$row" 2>/dev/null && echo ', running' || echo '')"
        [[ -f $MIG/$row.log ]] && tail -n 1 "$MIG/$row.log" | sed 's/^/    /'
    done
    echo "mounted:"
    findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep "$MIG/mnt" | sed 's/^/    /' || true
    ;;
*)
    echo "usage: $0 {plan ROW | start ROW | run ROW | attach ROW | status}   ROW = A, B, C or D" >&2
    exit 2
    ;;
esac
