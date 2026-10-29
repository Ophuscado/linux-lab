# Sourced by the loop tests. They run as root in a scratch Linux box (not on the Mac): each
# makes loop-device disks under $T (default /var/tmp/migtest), runs migrate-row.sh or
# snapraid-setup.sh against them and prints what to compare with the expected lines in its
# header. Needs losetup, parted, mkfs.ext4, xfsprogs, rsync, tmux, attr, python3 and mergerfs
# on PATH (the script's "mergerfs" command builds 2.42.0); unreadable-names.sh also mfusepy (pip).
T=${T:-/var/tmp/migtest}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$T/bin"
[ -x "$T/bin/mergerfs" ] || ln -sf "$(command -v mergerfs)" "$T/bin/mergerfs"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/dnf"; chmod +x "$T/bin/dnf"
printf '#!/bin/sh\nwhile [ "${1#--}" != "$1" ]; do shift; done\nexec "$@"\n' >"$T/bin/systemd-inhibit"; chmod +x "$T/bin/systemd-inhibit"
