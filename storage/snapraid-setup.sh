#!/usr/bin/env bash
# snapraid-setup.sh: the final layout of the disks after the migration: mounts by label, one
# mergerfs pool over the data disks, one SnapRAID array with 4 parity disks (6 at most, by the
# operator's 26 Oct decision, as the two 24-bay boxes fill: about one parity per 8 data disks).
#
# Layout (ROOT is /mnt):
#   /mnt/data/NN     data disk HD_NN, XFS, by label           28 of them (/mnt/hd/NN before 28 Oct)
#   /mnt/parity/NN   parity disks 24, 00, 08, 16, XFS, by label (apart from /mnt/data so the pool's
#                    /mnt/data/* can never take a parity disk in as a data branch)
#   /srv/pool        mergerfs over /mnt/data/*: new files go to a disk drawn at random,
#                    weighted by free space (pfrd); a disk that fills mid-file hands on
# SnapRAID: parity, 2-parity, 3-parity, 4-parity on the four parity disks (any four disks
# may fail); content files on the root filesystem and on four data disks spread over the boxes:
# SnapRAID wants one more copy than parity levels, each on a different disk, and rewrites every
# copy at every sync, so a copy on all disks would only slow syncs.
# Why 4: SnapRAID's table gives 4 parity for 22-28 data disks and 5 for 29-35 (the operator's
# rule: about one per 8). A whole 24-bay box failing is beyond any parity count: SnapRAID covers
# disks, the boxes' power and controllers are covered by keeping them on and watched.
# Only disks whose label carries XFS today are written into the conf and fstab (HD_33, still
# HFS+ while it is copied, comes in when 'install' runs again after its format).
#
#   snapraid-setup.sh conf      write snapraid.conf and the fstab block to var/snapraid/ and show them
#   snapraid-setup.sh install   put them in place: /etc/snapraid.conf, the fstab block
#                               (between marker lines, replaced on rerun), the mount points
#   snapraid-setup.sh mount     mount everything (after the migration; refuses while it runs)
#   snapraid-setup.sh owner [UID:GID]
#                               give the migrated files to you: every file and folder on the data
#                               disks owned by UID:GID (default 99:99, the "unknown" owner HFS+
#                               disks carry, found on the pool on 26 Oct) becomes yours; metadata
#                               only, all disks at once; prints the count per disk first
#   snapraid-setup.sh tools     mergerfs-tools (mergerfs.balance, .consolidate, .ctl, .dedup, .dup, .mktrash) at a pinned
#                               commit into ~/.local/bin; run them with sudo, e.g. sudo ~/.local/bin/
#                               mergerfs.balance /srv/pool (moves files from the fullest disks to the
#                               emptiest; before the first sync, or followed by one)
#   snapraid-setup.sh need      read only: per data disk, its files and the parity space they take
#                               at blocksize 256, 128 and 64 KiB (each file rounds up to whole
#                               blocks), against the smallest parity disk; run before 'first'
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

# Under sudo (or a root shell started from one) the plan and the migration stay the invoking user's.
UHOME=$(getent passwd "${SR_OWNER:-${SUDO_USER:-$(id -un)}}" | cut -d: -f6)
UHOME=${UHOME:-$HOME}
PLAN=${SR_PLAN:-$UHOME/disk-plan.csv}
ROOT=${SR_ROOT:-/mnt}
POOL=${SR_POOL:-/srv/pool}
ETC=${SR_ETC:-/etc}
UNITS=${SR_UNITS:-/etc/systemd/system}
CONTENT=${SR_CONTENT:-/var/snapraid}
MIG=${SR_MIG:-$UHOME/migrate}
OUT=${SR_OUT:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/var/snapraid}  # ignored by git

PARITY="24 00 08 16"              # one per box: A B C D
CONTENT_DISKS="25 01 09 17"       # four data disks spread over the boxes carry a content copy too
# mergerfs does not create new files on a disk with less free than this: headroom for SnapRAID,
# whose parity holds every file rounded up to whole blocks (see 'need'), and for XFS, which
# fragments when nearly full. 20G before 28 Oct.
# 900G leaves 15.5 TB of each 16.4 TB disk to the pool (operator, 28 Oct); raise it when 'need' says so.
MINFREE=${SR_MINFREE:-900G}
MARK_BEGIN="# snapraid-setup.sh begin"
MARK_END="# snapraid-setup.sh end"

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# Names of the disks in the plan, sorted.
names() { tail -n +2 "$PLAN" | cut -d, -f14 | grep -E '^[0-9]{2}$' | sort; }
is_parity() { [[ " $PARITY " == *" $1 "* ]]; }
# Labels that carry XFS now (no root needed): a disk of the plan that is not XFS yet stays out.
xfs_labels() {
    local l; l=$(lsblk -rno LABEL,FSTYPE 2>/dev/null | awk '$2 == "xfs" { print $1 }')
    # lsblk reads labels from udev; without its database (a container) blkid probes the devices.
    [[ -n $l ]] || l=$(blkid -s LABEL -s TYPE 2>/dev/null | sed -n 's/.*LABEL="\([^"]*\)".*TYPE="xfs".*/\1/p')
    printf '%s\n' "$l"
}
is_ready() { xfs_labels | grep -qx "HD_$1"; }
data_names() { local n; for n in $(names); do is_parity "$n" || ! is_ready "$n" || echo "$n"; done; }
waiting_names() { local n; for n in $(names); do is_ready "$n" || echo "$n"; done; }

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
        echo "# SnapRAID over the $(data_names | wc -l) data disks that are XFS now; written by snapraid-setup.sh"
        echo "# Four parity levels: any four disks may fail at once."
        i=1
        for n in $PARITY; do
            case $i in 1) echo "parity $ROOT/parity/$n/snapraid.parity" ;; *) echo "$i-parity $ROOT/parity/$n/snapraid.$i-parity" ;; esac
            i=$((i + 1))
        done
        echo
        echo "# Content files: the list of files and their hashes, one more copy than parity levels,"
        echo "# each on a different disk (root filesystem and four data disks); SnapRAID keeps them identical."
        echo "content $CONTENT/snapraid.content"
        for n in $CONTENT_DISKS; do is_ready "$n" && echo "content $ROOT/data/$n/.snapraid.content"; done
        echo
        echo "# Data disks, by bay name."
        for n in $(data_names); do echo "data d$n $ROOT/data/$n/"; done
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
        echo "# Data and parity disks, by label. nofail: a box that is off"
        echo "# does not hold up the boot; the device timeout bounds the wait for a slow tunnel."
        for n in $(data_names); do
            printf 'LABEL=HD_%s  %s/data/%s  xfs  noatime,nofail,x-systemd.device-timeout=30  0 0\n' "$n" "$ROOT" "$n"
            # Ordering only: the pool waits for each disk's mount to succeed or fail. With
            # requires-mounts-for (before 28 Oct) one absent disk kept the whole pool unmounted.
            reqs+=",x-systemd.after=$(systemd-escape -p --suffix=mount "$ROOT/data/$n")"
        done
        for n in $PARITY; do
            printf 'LABEL=HD_%s  %s/parity/%s  xfs  noatime,nofail,x-systemd.device-timeout=30  0 0\n' "$n" "$ROOT" "$n"
        done
        echo "# The pool: every data disk that is mounted. A disk that is absent is simply not in"
        echo "# the pool until the next mount."
        printf '%s/data/*  %s  fuse.mergerfs  allow_other,category.create=pfrd,moveonenospc=true,minfreespace=%s,cache.files=off,dropcacheonclose=true,fsname=pool,nofail%s  0 0\n' "$ROOT" "$POOL" "$MINFREE" "$reqs"
        local w; w=$(waiting_names | tr '\n' ' ')
        [[ -z $w ]] || echo "# Not XFS yet, left out until install runs again: $w"
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
        is_ready "$n" || continue
        if is_parity "$n"; then d=$ROOT/parity/$n; else d=$ROOT/data/$n; fi
        sudo mkdir -p "$d"
        # An empty mount point that cannot be written: when its disk is absent, nothing lands on the
        # root filesystem through the pool's glob or a path typed by hand (writes fail instead).
        mountpoint -q "$d" || sudo chattr +i "$d" 2>/dev/null || true
    done
    w=$(waiting_names | tr '\n' ' '); [[ -z $w ]] || echo "not XFS yet, left out of snapraid.conf and fstab until install runs again: $w"
    # The mount points of before 28 Oct (/mnt/hd/NN): removed when empty and unmounted, never otherwise.
    if [[ -d $ROOT/hd ]]; then
        for d in "$ROOT"/hd/*; do
            [[ -d $d ]] && ! mountpoint -q "$d" && [[ -z $(ls -A "$d" 2>/dev/null) ]] && { sudo chattr -i "$d" 2>/dev/null; sudo rmdir "$d"; } || true
        done
        sudo rmdir "$ROOT/hd" 2>/dev/null && echo "old mount points $ROOT/hd removed" || { [[ -d $ROOT/hd ]] && echo "WARN: $ROOT/hd kept: something in it is mounted or not empty"; }
    fi
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
need)
    # As root from the start, like owner: an hour of find on every disk outlasts sudo's ticket.
    if ((EUID != 0)); then exec sudo env SUDO_USER="${SUDO_USER:-$(id -un)}" SR_OWNER="${SR_OWNER:-}" SR_PLAN="$PLAN" SR_ROOT="$ROOT" SR_POOL="$POOL" bash "$0" "$@"; fi
    # Parity space per data disk: SnapRAID stores each file in whole blocks, so the parity disk must hold the
    # fullest data disk's sum of rounded-up sizes, plus slack. Reads metadata only (find), all disks at once.
    psize=$(for n in $PARITY; do findmnt -n "$ROOT/parity/$n" >/dev/null && df -B1 --output=size "$ROOT/parity/$n" | tail -n 1; done | sort -n | head -n 1 || true)
    [[ -n $psize ]] || die "no parity disk mounted under $ROOT/parity"
    awk -v p="$psize" 'BEGIN { printf "smallest parity disk: %.2f TB\n%-4s %10s %12s %14s %14s %14s\n", p / 1e12, "disk", "files", "used TB", "parity@256K", "parity@128K", "parity@64K" }'
    for n in $(data_names); do
        d=$ROOT/data/$n; findmnt -n "$d" >/dev/null || { echo "$n not mounted"; continue; }
        ( find "$d" -xdev -type f -printf '%s\n' 2>/dev/null | awk -v n="$n" -v p="$psize" '
            { f++; s += $1; for (i = 0; i < 3; i++) { b = 262144 / 2^i; r[i] += int(($1 + b - 1) / b) * b } }
            END { printf "%-4s %10d %12.2f", n, f, s / 1e12
                  for (i = 0; i < 3; i++) printf " %10.2f TB%s", r[i] / 1e12, ((r[i] > p * 0.98) ? "!" : " ")
                  print "" }' ) &
    done; wait
    echo "! : over 98% of the smallest parity disk at that blocksize: balance that disk down or use a smaller blocksize"
    ;;
mount)
    ! findmnt -n "$MIG/pool" >/dev/null || die "the migration pool is mounted; finish the migration first (migrate-row.sh status)"
    ! sudo tmux ls 2>/dev/null | grep -q '^mig-' || die "migration workers are running"
    sudo mount -a
    # The top folder of every disk and of the pool belongs to you, so new folders can be
    # made there; the migrated files keep the owner they had on the Mac.
    owner=${SUDO_USER:-$(id -un)}
    for n in $(data_names); do findmnt -n "$ROOT/data/$n" >/dev/null && sudo chown "$owner:$owner" "$ROOT/data/$n"; done
    echo "mounted:"; findmnt -n -o TARGET,SOURCE,SIZE,USED -l | grep -E "$ROOT/(data|parity)/|$POOL" | sed 's/^/    /'
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
tools)
    rev=940f2d08ee04ae11281a0471ce099572bd50ce9a   # trapexit/mergerfs-tools master, 27 Oct 2026
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    git -C "$tmp" init -q && git -C "$tmp" fetch -q --depth 1 https://github.com/trapexit/mergerfs-tools "$rev" &&
        git -C "$tmp" checkout -q FETCH_HEAD || die "cannot fetch mergerfs-tools $rev"
    mkdir -p "$HOME/.local/bin"
    for t in "$tmp"/src/mergerfs.*; do install -m 755 "$t" "$HOME/.local/bin/"; echo "installed ~/.local/bin/${t##*/}"; done
    ;;
owner)
    # As root from the start: the chowns of 28 disks outlast sudo's 5-minute ticket, and on 29 Oct the parallel jobs each
    # asked for the password again, unseen, and may have stopped. Running it again finishes what is left (--from).
    if ((EUID != 0)); then exec sudo env SUDO_USER="${SUDO_USER:-$(id -un)}" SR_OWNER="${SR_OWNER:-}" SR_PLAN="$PLAN" SR_ROOT="$ROOT" SR_POOL="$POOL" bash "$0" "$@"; fi
    from=${2:-99:99} owner=${SR_OWNER:-${SUDO_USER:-$(id -un)}}
    [[ $owner != root ]] || die "the new owner would be root: run it as your user, or set SR_OWNER=name"
    [[ $from =~ ^[0-9]+:[0-9]+$ ]] || die "owner takes UID:GID, e.g. 99:99"
    findmnt -n "$POOL" >/dev/null || die "$POOL is not mounted; run mount first"
    pids=()
    for n in $(data_names); do
        d=$ROOT/data/$n
        findmnt -n "$d" >/dev/null || { echo "$n not mounted, skipped"; continue; }
        ( c=$(find "$d" -xdev -uid "${from%:*}" -printf . | wc -c)
          chown -R -h --from="$from" "$owner:$owner" "$d" && echo "$n: $c entries now $owner" ) &
        pids+=($!)
    done
    rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
    ((rc == 0)) || die "a chown failed (see above)"
    echo "left with another owner at the top of the pool:"; find "$POOL" -maxdepth 1 ! -user "$owner" -printf '  %u:%g %m %p\n'
    ;;
first)
    [[ -f $ETC/snapraid.conf ]] || die "no $ETC/snapraid.conf; run install first"
    findmnt -n "$POOL" >/dev/null || die "$POOL is not mounted; run mount first"
    sudo mkdir -p "$CONTENT"
    echo "first sync: hashes every file on $(data_names | wc -w) data disks; hours to days; resumable (autosave)"
    sudo snapraid -c "$ETC/snapraid.conf" sync
    sudo snapraid -c "$ETC/snapraid.conf" scrub -p 2 -o 0
    sudo snapraid -c "$ETC/snapraid.conf" status | tail -n 20
    ;;
*)
    echo "usage: $0 {conf | install | mount | owner [UID:GID] | tools | first | timers on|off|status}" >&2
    exit 2
    ;;
esac
