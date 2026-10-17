#!/usr/bin/env bash
# backup-home.sh: back up your home folder to the backup disk with restic, one run at a time, at
# the lowest disk and CPU priority, so the migration and the desktop keep their share.
#
#   ./backup-home.sh [LABEL]               back up now; default LABEL "BACKUP (ext4)", the disk
#                                          must be mounted (plugging it in and opening it in
#                                          Dolphin does that)
#   ./backup-home.sh --if-present [LABEL]  the same, but quiet and done when the disk is not
#                                          there or a backup runs already (for a timer)
#   ./backup-home.sh snapshots [LABEL]     list the backups
#
# To look into a backup: restic -r '<disk>/restic' --password-file ~/.config/restic/password
# mount ~/restic-mnt (then browse ~/restic-mnt/snapshots/), or 'restore latest --target DIR'.
#
# The repository is <disk>/restic, made on the first run. Its password is read from
# RESTIC_PASSWORD_FILE, by default ~/.config/restic/password, which you write (mode 600). Keep a
# copy of it elsewhere, in a password manager: without it no backup can be read.
#
# Kept like Time Machine: one backup per hour for the last 24 hours, one per day for 31 days, one
# per week before that. While the disk is fuller than BACKUP_LIMIT percent (default 80), the
# oldest backup goes, one at a time, never the newest. Space of removed backups is reclaimed
# (prune, then a check of the repository) at most once a day, or at once when over the limit.
# Left out: ~/.cache, the trash, ~/migrate (the migration's logs and state), the password file and every folder
# marked with a CACHEDIR.TAG; other filesystems mounted under home are not followed.
# Run 'settings.sh usb-cap on' once, so a slow backup disk cannot stall the rest of the machine.

set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
mode=backup quiet=""
case ${1:-} in
--if-present) quiet=1; shift ;;
snapshots) mode=snapshots; shift ;;
esac
label=${1:-BACKUP (ext4)}
LIMIT=${BACKUP_LIMIT:-80}
[[ $LIMIT =~ ^[1-9][0-9]?$ ]] || die "BACKUP_LIMIT is a percentage, 1 to 99"
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/backup-home
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}

command -v restic >/dev/null || die "restic is not installed: sudo dnf install restic"
dst=$(findmnt -n -o TARGET -S "LABEL=$label" 2>/dev/null | head -n 1 || true)
if [[ -z $dst ]]; then
    [[ -n $quiet ]] && exit 0
    die "the disk labeled '$label' is not mounted: plug it in and open it in Dolphin"
fi
pw=$RESTIC_PASSWORD_FILE
[[ -s $pw ]] || die "no password in $pw: make the file with 'install -D -m 600 /dev/null $pw', paste a long password into it, and keep a copy in your password manager"
[[ $(stat -c %a "$pw") =~ ^[46]00$ ]] || die "$pw can be read by others (mode $(stat -c %a "$pw")): chmod 600 $pw"
export RESTIC_REPOSITORY=$dst/restic

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/backup-home.lock"
if ! flock -n 9; then
    [[ -n $quiet ]] && exit 0
    die "a backup is running already"
fi
r() { ionice -c3 nice -n 19 restic "$@"; }
count() { r snapshots --tag home --json | python3 -c 'import json, sys; print(len(json.load(sys.stdin) or []))'; }
used() { df --output=pcent "$dst" | tail -n 1 | tr -dc 0-9; }

if [[ $mode == snapshots ]]; then
    [[ -f $RESTIC_REPOSITORY/config ]] || die "no backup on '$label' yet"
    r snapshots --tag home
    exit 0
fi
if [[ ! -f $RESTIC_REPOSITORY/config ]]; then
    echo "making the restic repository $RESTIC_REPOSITORY"
    r init
fi
echo "backing up $HOME to $RESTIC_REPOSITORY"
rc=0
r backup --one-file-system --exclude-caches --tag home \
    --exclude "$HOME/.cache" --exclude "$HOME/.local/share/Trash" --exclude "$HOME/migrate" --exclude "$pw" "$HOME" || rc=$?
case $rc in
0) ;;
3) echo "WARN: some files could not be read (listed above); the backup holds all the others" >&2 ;;
*) die "restic backup failed (code $rc); the backups made before are untouched" ;;
esac

r forget --tag home --keep-hourly 24 --keep-daily 31 --keep-weekly unlimited
mkdir -p "$STATE"
if [[ -z $(find "$STATE/pruned" -mmin -1440 2>/dev/null) ]] || (($(used) > LIMIT)); then
    r prune
    r check
    touch "$STATE/pruned"
fi
while (($(used) > LIMIT)); do
    n=$(count)
    if ((n <= 1)); then
        echo "WARN: the disk is $(used) % full with only the newest backup left (limit $LIMIT %)" >&2
        break
    fi
    echo "the disk is $(used) % full (limit $LIMIT %): the oldest of $n backups goes"
    r forget --tag home --keep-last $((n - 1)) --prune
done
echo "done: $(count) backups on '$label', the disk is $(used) % full"
exit "$rc"
