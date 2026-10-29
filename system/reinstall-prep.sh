#!/bin/bash
# reinstall-prep.sh: run in macOS before installing Fedora Asahi again on the Mac Studio.
# It removes the old Linux installation and works out the size macOS has to shrink to so
# that the new Linux root gets a fixed amount (3.5 TB by default).
#
#   reinstall-prep.sh plan     read-only: checks the partition table against the one this
#                              was written for and prints what would happen and the number
#                              to give the installer
#   reinstall-prep.sh delete   deletes the four partitions of the old installation (its
#                              boot stub, its EFI partition, /boot and the root), after
#                              you type a confirmation. Everything on them is lost
#
# Then, still in macOS: set macOS as the startup disk (System Settings, General, Startup
# Disk), run the installer (curl https://fedora-asahi-remix.org/install | sh), choose
# "resize an existing partition", give it the number plan printed, and then install into
# the free space with the default size "max".
#
# Written for this layout of disk0 (diskutil list, 2026-10-13); anything else is refused:
#   s1 system container · s2 macOS · s3 Fedora stub (APFS, 2.5 GB) · s4 EFI of Fedora ·
#   s5 and s6 Linux · s7 recovery
# Never touched: s1, s2 and s7. macOS upgrades stop working without the recovery partition.
#
# Sizes: disks and the installer count in decimal units (1 TB = 10^12 bytes); Linux shows
# the same 3.5 TB as 3.2T because it counts in binary ones.
#
# Environment: ROOT_BYTES (what the Linux root should get, default 3500000000000).

set -eu

DISK=disk0
ROOT_BYTES=${ROOT_BYTES:-3500000000000}
# What the installer puts in front of the root: its boot stub, an EFI partition and /boot.
STUB=2500000000
EFI=$((500 * 1024 * 1024))
BOOTP=$((1024 * 1024 * 1024))
# The root ends up this much above the target at least, and by up to SLACK more: diskutil
# and the installer round sizes, and too little would mean a root under the target.
PAD=$((100 * 1000 * 1000))
SLACK=$((256 * 1024 * 1024))
PB=${PB:-/usr/libexec/PlistBuddy}

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

row() { diskutil list "$DISK" | awk -v id="$1" '$NF == id'; }
# A number from "diskutil info": Size or PartitionMapPartitionOffset, in bytes.
num() {
    local v
    v=$(diskutil info -plist "$1" | "$PB" -c "Print :$2" /dev/stdin 2>/dev/null) || v=
    case $v in
    '' | *[!0-9]*) die "could not read $2 of $1; send the output of: diskutil info $1" ;;
    esac
    echo "$v"
}
gb() { awk -v b="$1" 'BEGIN { printf "%.1f GB", b / 1e9 }'; }

check_layout() {
    local bootc stubc
    [ "$(uname -s)" = Darwin ] || die "this runs in macOS"
    bootc=$(df / | awk 'NR == 2 { print $1 }' | sed 's|^/dev/\(disk[0-9]*\).*|\1|')
    case $bootc in disk[0-9]*) ;; *) die "could not tell which container macOS runs from" ;; esac

    row "${DISK}s1" | grep -q 'Apple_APFS_ISC' || die "${DISK}s1 is not the system container"
    row "${DISK}s2" | grep -q "Apple_APFS Container $bootc " || die "${DISK}s2 is not the macOS you are running ($bootc)"
    row "${DISK}s3" | grep -q 'Apple_APFS Container disk[0-9]' || die "${DISK}s3 is not an APFS container"
    row "${DISK}s4" | grep -q ' EFI .*FEDOR' || die "${DISK}s4 is not Fedora's EFI partition"
    row "${DISK}s5" | grep -q 'Linux Filesystem' || die "${DISK}s5 is not a Linux partition"
    row "${DISK}s6" | grep -q 'Linux Filesystem' || die "${DISK}s6 is not a Linux partition"
    row "${DISK}s7" | grep -q 'Apple_APFS_Recovery' || die "${DISK}s7 is not the recovery partition"
    [ -z "$(row "${DISK}s8")" ] || die "there is a ${DISK}s8; this was written for seven partitions"

    stubc=$(row "${DISK}s3" | sed -n 's/.*Container \(disk[0-9]*\) .*/\1/p')
    [ -n "$stubc" ] && [ "$stubc" != "$bootc" ] || die "${DISK}s3 belongs to the running macOS"
    diskutil list "$stubc" | grep -q 'Fedora' || die "the container on ${DISK}s3 ($stubc) has no Fedora volume"
    local s3
    s3=$(num "${DISK}s3" Size)
    [ "$s3" -gt 2000000000 ] && [ "$s3" -lt 3000000000 ] || die "${DISK}s3 is $(gb "$s3"), not a 2.5 GB boot stub"
}

# The size macOS has to have so that the space between it and the recovery partition is
# what Linux needs.
macos_size() {
    local o2 o7 linux
    o2=$(num "${DISK}s2" PartitionMapPartitionOffset)
    o7=$(num "${DISK}s7" PartitionMapPartitionOffset)
    linux=$((ROOT_BYTES + PAD + STUB + EFI + BOOTP))
    echo $(((o7 - o2 - linux - SLACK) / 1048576 * 1048576))
}

stage_plan() {
    local x cur
    check_layout
    x=$(macos_size)
    cur=$(num "${DISK}s2" Size)
    echo "The partition table is the one this was written for."
    echo
    echo "delete would remove:"
    for p in 3 4 5 6; do row "${DISK}s$p"; done
    echo
    echo "macOS is $(gb "$cur") now. For a Linux root of $(gb "$ROOT_BYTES") it has to become $(gb "$x")."
    [ "$x" -gt 100000000000 ] || die "that leaves macOS only $(gb "$x"); choose a smaller ROOT_BYTES"
    if [ "$x" -ge "$cur" ]; then
        echo "macOS does not have to shrink: skip the resize and, at 'New OS size', give the"
        echo "installer $((ROOT_BYTES + PAD + STUB + EFI + BOOTP + SLACK)) instead of max."
    else
        echo "In the installer:"
        echo "  resize an existing partition, 'New size':   $x"
        echo "  install into free space, 'New OS size':     max  (just press Enter)"
        echo "The number is in bytes. The installer refuses it if macOS holds more than fits, and says so."
        echo "Linux then gets a root of $(gb $((ROOT_BYTES + PAD))) to $(gb $((ROOT_BYTES + PAD + SLACK))), shown there as about $(awk -v b="$ROOT_BYTES" 'BEGIN { printf "%.1fT", b / 1024 / 1024 / 1024 / 1024 }')."
    fi
}

# $1 partition number, $2 offset it had when checked, $3 pattern its row must still match.
same_partition() {
    [ "$(num "${DISK}s$1" PartitionMapPartitionOffset)" = "$2" ] && row "${DISK}s$1" | grep -q "$3"
}

stage_delete() {
    local o3 o4 o5 o6 answer left
    check_layout
    o3=$(num "${DISK}s3" PartitionMapPartitionOffset)
    o4=$(num "${DISK}s4" PartitionMapPartitionOffset)
    o5=$(num "${DISK}s5" PartitionMapPartitionOffset)
    o6=$(num "${DISK}s6" PartitionMapPartitionOffset)
    stage_plan
    echo
    echo "This deletes the Linux installation: everything in it, /home included, is gone for good."
    printf "Type 'delete linux' to go ahead: "
    read -r answer </dev/tty
    [ "$answer" = "delete linux" ] || die "not confirmed; nothing changed"

    # From the back, and each one only if it still is where and what it was a moment ago.
    same_partition 6 "$o6" 'Linux Filesystem' || die "${DISK}s6 changed; nothing deleted"
    diskutil eraseVolume free free "${DISK}s6"
    same_partition 5 "$o5" 'Linux Filesystem' || die "${DISK}s5 changed; stopped after s6"
    diskutil eraseVolume free free "${DISK}s5"
    same_partition 4 "$o4" ' EFI .*FEDOR' || die "${DISK}s4 changed; stopped after s5"
    diskutil eraseVolume free free "${DISK}s4"
    same_partition 3 "$o3" 'Apple_APFS Container disk[0-9]' || die "${DISK}s3 changed; stopped after s4"
    diskutil apfs deleteContainer "${DISK}s3"
    # Deleting a container can leave an empty partition in its place.
    left=$(row "${DISK}s3")
    if [ -n "$left" ] && [ "$(num "${DISK}s3" PartitionMapPartitionOffset)" = "$o3" ]; then
        case $left in
        *Apple_APFS*) die "${DISK}s3 is still an APFS partition; send: diskutil list" ;;
        *) diskutil eraseVolume free free "${DISK}s3" ;;
        esac
    fi

    echo
    diskutil list "$DISK"
    echo "Done. Next: set macOS as the startup disk, then run the installer with the numbers above."
}

case ${1:-} in
plan) stage_plan ;;
delete) stage_delete ;;
*)
    echo "usage: $0 {plan | delete}" >&2
    exit 2
    ;;
esac
