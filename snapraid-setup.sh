#!/usr/bin/env bash
# snapraid-setup.sh: the final layout of the 32 disks, after the migration: mounts by label,
# one mergerfs pool over the 28 data disks, one SnapRAID array with 4 parity disks.
#
# Layout (ROOT is /mnt):
#   /mnt/hd/NN       data disk HD_NN, XFS, by label           28 of them
#   /mnt/parity/NN   parity disk 24, 00, 08, 16 (one per box), XFS, by label
#   /srv/pool        mergerfs over /mnt/hd/*: new files go to a disk drawn at random,
#                    weighted by free space (pfrd); a disk that fills mid-file hands on
# SnapRAID: parity, 2-parity, 3-parity, 4-parity on the four parity disks (any four disks
# may fail); content files on the root filesystem and on one data disk per box.
# Why 4: SnapRAID's own table gives 4 parity for up to 28 data disks; the boxes fail as a
# unit (power, controller), so the double fault is realistic.
#
#   snapraid-setup.sh conf      write snapraid.conf and the fstab block to ./out/ and show them
#   snapraid-setup.sh install   put them in place: /etc/snapraid.conf, the fstab block
#                               (between marker lines, replaced on rerun), the mount points
#   snapraid-setup.sh mount     mount everything (after the migration; refuses while it runs)
#   snapraid-setup.sh first     the first "snapraid sync" (hours: hashes every file) and a
#                               short scrub
#   snapraid-setup.sh timers on|off|status
#                               systemd timers: sync nightly at 03:10, scrub 3 % of the
#                               oldest blocks weekly (Sunday 04:10); a sync stops itself
#                               when more than 500 files were deleted (a lost disk or a
#                               mistake), for you to look first
#
# Needs ~/disk-plan.csv from disk-inventory.sh with every disk named; snapraid and mergerfs
# installed. Test hooks: SR_PLAN, SR_ROOT, SR_POOL, SR_ETC (where snapraid.conf and fstab
# live), SR_CONTENT (the content directory on the root filesystem), SR_MIG (the migration's
# home, to refuse mounting while it runs).

set -euo pipefail

PLAN=${SR_PLAN:-$HOME/disk-plan.csv}
ROOT=${SR_ROOT:-/mnt}
POOL=${SR_POOL:-/srv/pool}
ETC=${SR_ETC:-/etc}
UNITS=${SR_UNITS:-/etc/systemd/system}
CONTENT=${SR_CONTENT:-/var/snapraid}
MIG=${SR_MIG:-$HOME/migrate}
OUT=${SR_OUT:-$PWD/out}

PARITY="24 00 08 16"              # one per box: A B C D
CONTENT_DISKS="25 01 09 17"       # one data disk per box carries a content copy too
MARK_BEGIN="# snapraid-setup.sh begin"
MARK_END="# snapraid-setup.sh end"

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# Names of the disks in the plan, sorted.
names() { tail -n +2 "$PLAN" | cut -d, -f14 | grep -E '^[0-9]{2}$' | sort; }
is_parity() { [[ " $PARITY " == *" $1 "* ]]; }
data_names() { local n; for n in $(names); do is_parity "$n" || echo "$n"; done; }

check_plan() {
    [[ -r $PLAN ]] || die "no $PLAN; run disk-inventory.sh first"
    ! grep -q ',?$' "$PLAN" || die "$PLAN still has unnamed disks"
    [[ $(names | uniq -d | wc -l) == 0 ]] || die "$PLAN names a disk twice"
    local n
    for n in $PARITY; do names | grep -qx "$n" || die "parity disk $n is not in $PLAN"; done
    [[ $(names | wc -l) == 32 ]] || echo "WARN: $PLAN lists $(names | wc -l) disks, not 32" >&2
}

write_conf() {
    local n i=0
    {
        echo "# SnapRAID over the 28 data disks of the four enclosures; written by snapraid-setup.sh"
        echo "# Four parity levels: any four disks may fail at once."
        i=1
        for n in $PARITY; do
            case $i in 1) echo "parity $ROOT/parity/$n/snapraid.parity" ;; *) echo "$i-parity $ROOT/parity/$n/snapraid.$i-parity" ;; esac
            i=$((i + 1))
        done
        echo
        echo "# Content files: the list of files and their hashes. One on the root filesystem,"
        echo "# one on a data disk in each box; SnapRAID keeps them identical."
        echo "content $CONTENT/snapraid.content"
        for n in $CONTENT_DISKS; do echo "content $ROOT/hd/$n/.snapraid.content"; done
        echo
        echo "# Data disks, by bay name."
        for n in $(data_names); do echo "data d$n $ROOT/hd/$n/"; done
        echo
        echo "# Never protected: SnapRAID's own leftovers, lost+found, trash folders, the pool's"
        echo "# and mergerfs' control files."
        echo "exclude *.unrecoverable"
        echo "exclude /lost+found/"
        echo "exclude /.Trash*/"
        echo "exclude /.mergerfs"
        echo "exclude .DS_Store"
        echo "exclude ._*"
        echo "exclude .fseventsd/"
        echo "exclude .Spotlight-V100/"
        echo
        echo "# 256 KiB blocks (the default) suit files of megabytes; the content file stays"
        echo "# around 30 bytes per block plus one entry per file. hashsize 16 is the default."
        echo "blocksize 256"
        echo "hashsize 16"
        echo "# Save the content files every 500 GB of a sync, so an interrupted first sync"
        echo "# (days) keeps its progress."
        echo "autosave 500"
    } >"$OUT/snapraid.conf"
}

write_fstab() {
    local n reqs=""
    {
        echo "$MARK_BEGIN"
        echo "# Data and parity disks of the four enclosures, by label. nofail: a box that is off"
        echo "# does not hold up the boot; the device timeout bounds the wait for a slow tunnel."
        for n in $(data_names); do
            printf 'LABEL=HD_%s  %s/hd/%s  xfs  noatime,nofail,x-systemd.device-timeout=30  0 0\n' "$n" "$ROOT" "$n"
            reqs+=",x-systemd.requires-mounts-for=$ROOT/hd/$n"
        done
        for n in $PARITY; do
            printf 'LABEL=HD_%s  %s/parity/%s  xfs  noatime,nofail,x-systemd.device-timeout=30  0 0\n' "$n" "$ROOT" "$n"
        done
        echo "# The pool: every data disk that is mounted. A disk that is absent is simply not in"
        echo "# the pool until the next mount."
        printf '%s/hd/*  %s  fuse.mergerfs  category.create=pfrd,moveonenospc=true,minfreespace=20G,cache.files=off,dropcacheonclose=true,fsname=pool,nofail%s  0 0\n' "$ROOT" "$POOL" "$reqs"
        echo "$MARK_END"
    } >"$OUT/fstab.block"
}

case ${1:-} in
conf)
    check_plan
    mkdir -p "$OUT"
    write_conf
    write_fstab
    echo "wrote $OUT/snapraid.conf and $OUT/fstab.block:"
    echo; cat "$OUT/snapraid.conf"; echo; cat "$OUT/fstab.block"
    ;;
install)
    check_plan
    mkdir -p "$OUT"
    write_conf
    write_fstab
    command -v snapraid >/dev/null || sudo dnf install -y snapraid
    sudo install -D -m 644 "$OUT/snapraid.conf" "$ETC/snapraid.conf"
    sudo mkdir -p "$CONTENT" "$POOL"
    for n in $(names); do
        if is_parity "$n"; then sudo mkdir -p "$ROOT/parity/$n"; else sudo mkdir -p "$ROOT/hd/$n"; fi
    done
    # The fstab block replaces an earlier one between the markers, or is appended.
    sudo touch "$ETC/fstab"
    # shellcheck disable=SC2024
    sudo awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$ETC/fstab" >"$OUT/fstab.new"
    cat "$OUT/fstab.block" >>"$OUT/fstab.new"
    sudo cp "$ETC/fstab" "$OUT/fstab.before"
    sudo install -m 644 "$OUT/fstab.new" "$ETC/fstab"
    sudo systemctl daemon-reload 2>/dev/null || true
    echo "installed $ETC/snapraid.conf and the fstab block (previous fstab kept at $OUT/fstab.before)"
    ;;
mount)
    ! findmnt -n "$MIG/pool" >/dev/null || die "the migration pool is mounted; finish the migration first (migrate-row.sh status)"
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-' || die "migration workers are running"
    sudo mount -a
    echo "mounted:"; findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep -E "$ROOT/(hd|parity)/|$POOL" | sed 's/^/    /'
    ;;
timers)
    case ${2:-} in
    on)
        [[ -f $ETC/snapraid.conf ]] || die "no $ETC/snapraid.conf; run install first"
        sudo mkdir -p "$UNITS"
        printf '%s\n' '[Unit]' 'Description=SnapRAID sync (parity update); refuses when a data disk reads empty' \
            'ConditionPathIsMountPoint='"$POOL" '' '[Service]' 'Type=oneshot' 'Nice=10' 'IOSchedulingClass=idle' \
            'ExecStart=/usr/bin/snapraid -c '"$ETC/snapraid.conf"' sync -h' |
            sudo tee "$UNITS/snapraid-sync.service" >/dev/null
        printf '%s\n' '[Unit]' 'Description=SnapRAID sync nightly' '' '[Timer]' 'OnCalendar=*-*-* 03:10' 'Persistent=true' 'RandomizedDelaySec=10m' '' '[Install]' 'WantedBy=timers.target' |
            sudo tee "$UNITS/snapraid-sync.timer" >/dev/null
        printf '%s\n' '[Unit]' 'Description=SnapRAID scrub: 3 percent of the oldest blocks' 'ConditionPathIsMountPoint='"$POOL" '' '[Service]' 'Type=oneshot' 'Nice=10' 'IOSchedulingClass=idle' \
            'ExecStart=/usr/bin/snapraid -c '"$ETC/snapraid.conf"' scrub -p 3 -o 30' |
            sudo tee "$UNITS/snapraid-scrub.service" >/dev/null
        printf '%s\n' '[Unit]' 'Description=SnapRAID scrub weekly' '' '[Timer]' 'OnCalendar=Sun *-*-* 04:10' 'Persistent=true' '' '[Install]' 'WantedBy=timers.target' |
            sudo tee "$UNITS/snapraid-scrub.timer" >/dev/null
        sudo systemctl daemon-reload
        sudo systemctl enable --now snapraid-sync.timer snapraid-scrub.timer
        systemctl list-timers --no-pager 'snapraid-*'
        ;;
    off)
        sudo systemctl disable --now snapraid-sync.timer snapraid-scrub.timer 2>/dev/null || true
        sudo rm -f "$UNITS"/snapraid-{sync,scrub}.{service,timer}
        sudo systemctl daemon-reload
        echo "timers removed"
        ;;
    status) systemctl list-timers --no-pager 'snapraid-*'; systemctl --no-pager status snapraid-sync.service snapraid-scrub.service 2>/dev/null | grep -E 'Active|snapraid' | head -n 6 ;;
    *) die "usage: $0 timers on|off|status" ;;
    esac
    ;;
first)
    [[ -f $ETC/snapraid.conf ]] || die "no $ETC/snapraid.conf; run install first"
    findmnt -n "$POOL" >/dev/null || die "$POOL is not mounted; run mount first"
    sudo mkdir -p "$CONTENT"
    echo "first sync: hashes every file on 28 disks; hours to days; resumable (autosave)"
    sudo snapraid -c "$ETC/snapraid.conf" sync
    sudo snapraid -c "$ETC/snapraid.conf" scrub -p 2 -o 0
    sudo snapraid -c "$ETC/snapraid.conf" status | tail -n 20
    ;;
*)
    echo "usage: $0 {conf | install | mount | first | timers on|off|status}" >&2
    exit 2
    ;;
esac
