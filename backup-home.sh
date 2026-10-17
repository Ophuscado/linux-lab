#!/usr/bin/env bash
# backup-home.sh: copy your home folder to the backup disk, one copy at a time, at the lowest
# disk and CPU priority, so the migration and the desktop keep their share.
#
#   ./backup-home.sh [LABEL]     default LABEL "BACKUP (ext4)"; the disk must be mounted
#                                (plugging it in and opening it in Dolphin does that)
#
# Copies to <disk>/home_backup/ with rsync -ax --delete, as before, but: a second run while one
# is going refuses (two at once into the same folder left both stuck on 16 Oct); ~/.cache, the
# trash and ~/migrate (the migration's logs and state, gigabytes of progress lines) stay out.
# Run 'settings.sh usb-cap on' once, so a slow backup disk cannot stall the rest of the machine.

set -euo pipefail
label=${1:-BACKUP (ext4)}
dst=$(findmnt -n -o TARGET -S "LABEL=$label" 2>/dev/null | head -n 1 || true)
[[ -n $dst ]] || { echo "the disk labeled '$label' is not mounted: plug it in and open it in Dolphin" >&2; exit 1; }
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/backup-home.lock"
flock -n 9 || { echo "a backup is running already" >&2; exit 1; }
echo "backing up $HOME to $dst/home_backup/"
mkdir -p "$dst/home_backup"
ionice -c3 nice -n 19 rsync -ax --delete --info=progress2,stats1 \
    --exclude=/.cache/ --exclude=/.local/share/Trash/ --exclude=/migrate/ \
    "$HOME/" "$dst/home_backup/"
