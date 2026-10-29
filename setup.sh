#!/usr/bin/env bash
# setup.sh: take a fresh Fedora Asahi install on the Mac Studio to the lab's state, and
# keep snapshots it can be put back to without installing again.
#
# On a fresh install, get this one file and run it:
#   curl -fsSLO https://raw.githubusercontent.com/Ophuscado/linux-lab/master/setup.sh
#   bash setup.sh all
# Afterwards it lives in ~/linux-lab with the other scripts.
#
#   all        repo, bluetooth, snapshot, kernel, tools, in that order (about 45 minutes,
#              nearly all of it the kernel build). Ends asking for a reboot
#   repo       clone https://github.com/Ophuscado/linux-lab into ~/linux-lab (the kernel
#              work in its kernel/), or bring an existing clone up to date.
#              Run it again whenever there are new scripts
#   bluetooth  bt-sync.sh: Linux takes the pairings macOS made (pair there first)
#   snapshot [NAME]   keep the system as it is now under NAME (default clean-<date>):
#              read-only btrfs snapshots of / and /home, plus archives of /boot and of the
#              EFI partition, which hold the kernels and the boot image and are not btrfs
#   kernel     kernel/tbt-kernel.sh deps, build, install, try: the lab's kernel
#              becomes the one Linux boots (GPU, USB4, PCIe over Thunderbolt); then
#              tbt-disks.sh readonly on and authorize on, as tbt-kernel.sh install did until
#              18 Oct. Reboot afterwards
#   tools      packages the measuring scripts need, so they run without installing
#   list       the snapshots
#   restore NAME [--home]   put the system back to snapshot NAME: /, /boot and the boot
#              image; with --home also /home, otherwise /home stays as it is today.
#              Takes a snapshot of the present state first (before-restore-<time>), so a
#              restore is undone by restoring that one. Takes effect at the next boot
#   cleanup    after a restore and a reboot: delete the replaced copies of / and /home
#   drop NAME  delete a snapshot
#
# How a restore works: the filesystem has two subvolumes, root and home, and Linux mounts
# them by name. restore renames the running root to root.replaced-<time> and makes a new
# root from the snapshot, so the next boot uses the new one; nothing is deleted until
# cleanup. /boot and the EFI partition are rewritten from the archives, because a kernel
# is spread over /boot (image, initramfs, device trees), / (modules) and the boot image.
#
# Snapshots live in lab-snapshots/ at the top of the filesystem, readable by root only.
# They share blocks with the live system: a snapshot costs space only as things change.
#
# Test hooks: LAB_TOP (top level already mounted), LAB_BOOT, LAB_ESP, LAB_REPO.

set -euo pipefail

REPO=${LAB_REPO:-https://github.com/Ophuscado/linux-lab}
LAB=${LAB:-$HOME/linux-lab}
# The kernel work, in the lab's kernel/ since 27 Oct (the linux-patches repository before).
KLAB=${KLAB:-$LAB/kernel}
SNAPDIR=lab-snapshots
TOP=${LAB_TOP:-}
BOOT=${LAB_BOOT:-/boot}
ESP=${LAB_ESP:-/boot/efi}
MNT=/run/lab-top
EXPECT_KERNEL=7.1.13

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# Mount the top of the btrfs filesystem, where the subvolumes root and home are entries.
open_top() {
    [[ -z $TOP ]] || return 0
    local src dev
    src=$(findmnt -no SOURCE /)
    [[ $(findmnt -no FSTYPE /) == btrfs && $src == *"[/root]" ]] ||
        die "expected / on the btrfs subvolume 'root', found: $(findmnt -no FSTYPE,SOURCE /)"
    dev=${src%%\[*}
    [[ $(findmnt -no SOURCE /home) == "${dev}[/home]" ]] ||
        die "expected /home on the subvolume 'home' of $dev, found: $(findmnt -no SOURCE /home)"
    mountpoint -q "$BOOT" || die "$BOOT is not a separate partition"
    mountpoint -q "$ESP" || die "$ESP is not mounted"
    sudo mkdir -p "$MNT"
    mountpoint -q "$MNT" || sudo mount -o subvolid=5 "$dev" "$MNT"
    trap 'sudo umount "$MNT" 2>/dev/null || true' EXIT
    TOP=$MNT
    sudo test -d "$TOP/root" -a -d "$TOP/home" || die "no root and home at the top of $dev"
}

check_name() {
    [[ ${1:-} =~ ^[A-Za-z0-9._-]+$ ]] || die "a snapshot name may use letters, digits, dot, dash and underscore"
}

# $1 name. Everything a later restore needs goes into one directory.
take_snapshot() {
    local name=$1 dir
    dir=$TOP/$SNAPDIR/$name
    sudo test ! -e "$dir" || die "snapshot $name exists already"
    sudo install -d -m 0700 "$TOP/$SNAPDIR"
    sudo mkdir "$dir"
    sudo btrfs subvolume snapshot -r "$TOP/root" "$dir/root" >/dev/null
    sudo btrfs subvolume snapshot -r "$TOP/home" "$dir/home" >/dev/null
    # The EFI partition is mounted inside /boot and archived on its own.
    sudo tar --xattrs --acls --selinux --one-file-system --exclude=./efi --exclude=./lost+found \
        -cpf "$dir/boot.tar" -C "$BOOT" .
    sudo tar -cf "$dir/esp.tar" -C "$ESP" .
    sudo tar -tf "$dir/boot.tar" >/dev/null || die "the archive of $BOOT does not read back"
    sudo tar -tf "$dir/esp.tar" >/dev/null || die "the archive of $ESP does not read back"
    {
        echo "taken: $(date '+%Y-%m-%d %H:%M')"
        echo "running kernel: $(uname -r)"
        echo "default kernel: $(sudo grubby --default-kernel 2>/dev/null || echo unknown)"
        echo "device trees: $(readlink "$BOOT/dtb" 2>/dev/null || echo unknown)"
        echo "kernels: $(sudo find "$BOOT" -maxdepth 1 -name 'vmlinuz-*' ! -name '*rescue*' -printf '%f ' | tr ' ' '\n' | sort | tr '\n' ' ')"
    } | sudo tee "$dir/info.txt" >/dev/null
}

# $1 snapshot directory. Kernels, initramfs, device trees and boot entries, then the boot image.
restore_boot() {
    local dir=$1
    [[ $BOOT == /boot || -n ${LAB_BOOT:-} ]] || return 1
    sudo find "$BOOT" -mindepth 1 -maxdepth 1 ! -name efi ! -name lost+found -exec rm -rf {} + &&
        sudo tar --xattrs --acls --selinux -xpf "$dir/boot.tar" -C "$BOOT" &&
        sudo tar --no-same-owner --no-same-permissions -xf "$dir/esp.tar" -C "$ESP"
}

stage_repo() {
    command -v git >/dev/null || sudo dnf install -y git-core
    local r d
    for r in "$REPO $LAB"; do
        d=${r#* }
        if [[ -d $d/.git ]]; then
            git -C "$d" pull --ff-only
        else
            git clone "${r%% *}" "$d"
        fi
        echo "scripts are in $d at $(git -C "$d" log -1 --format='%h %s')"
    done
}

need_repo() {
    [[ -x $LAB/system/settings.sh ]] || die "no scripts in $LAB yet; run: $0 repo"
    [[ -x $KLAB/tbt-kernel.sh ]] || die "no kernel scripts in $KLAB yet; run: $0 repo"
}

stage_bluetooth() {
    need_repo
    "$LAB/desktop/bt-sync.sh"
}

stage_snapshot() {
    local name=${1:-clean-$(date +%Y%m%d-%H%M)}
    check_name "$name"
    open_top
    take_snapshot "$name"
    echo "snapshot $name taken:"
    sudo cat "$TOP/$SNAPDIR/$name/info.txt"
    echo "Put the system back to it with: $0 restore $name"
}

stage_kernel() {
    need_repo
    [[ $(uname -r) == "$EXPECT_KERNEL"* ]] ||
        echo "WARN: this install runs $(uname -r); the lab's kernel is built from $EXPECT_KERNEL and was only tested beside that one."
    "$KLAB/tbt-kernel.sh" deps
    "$KLAB/tbt-kernel.sh" build
    "$KLAB/tbt-kernel.sh" install
    "$LAB/storage/tbt-disks.sh" readonly on
    "$LAB/storage/tbt-disks.sh" authorize on
    "$KLAB/tbt-kernel.sh" try
}

stage_tools() {
    need_repo
    say "packages for the measuring scripts"
    sudo dnf install -y hdparm smartmontools pciutils usbutils nmap-ncat vulkan-tools
    "$LAB/gpu/llama-bench.sh" deps
    "$LAB/gpu/mesa-side.sh" deps
    say "ready. What is waiting to be measured ($LAB/_gtd/DOING.md):"
    sed 's/ · check:.*//; s/^/  - /' "$LAB/_gtd/DOING.md"
}

stage_list() {
    local d
    open_top
    sudo test -d "$TOP/$SNAPDIR" || { echo "no snapshots yet"; return; }
    for d in $(sudo ls "$TOP/$SNAPDIR"); do
        printf '%s\n' "$d"
        sudo sed 's/^/    /' "$TOP/$SNAPDIR/$d/info.txt" 2>/dev/null || echo "    (incomplete)"
    done
}

stage_restore() {
    local name=${1:-} home=${2:-} dir ts before answer
    check_name "$name"
    [[ -z $home || $home == --home ]] || die "usage: $0 restore NAME [--home]"
    open_top
    dir=$TOP/$SNAPDIR/$name
    sudo test -d "$dir/root" -a -f "$dir/boot.tar" -a -f "$dir/esp.tar" ||
        die "snapshot $name is missing or incomplete; see: $0 list"
    [[ -z $home ]] || sudo test -d "$dir/home" || die "snapshot $name has no home"
    ts=$(date +%Y%m%d-%H%M%S)
    while sudo test -e "$TOP/$SNAPDIR/before-restore-$ts" -o -e "$TOP/root.replaced-$ts"; do
        sleep 1
        ts=$(date +%Y%m%d-%H%M%S)
    done
    before=before-restore-$ts

    say "restore $name"
    sudo sed 's/^/    /' "$dir/info.txt"
    echo "This replaces /, $BOOT and the boot image with that state${home:+, and /home too}."
    [[ -n $home ]] || echo "/home stays as it is now."
    echo "The present state is kept first as snapshot $before."
    read -r -p "Type the snapshot name to go ahead: " answer </dev/tty
    [[ $answer == "$name" ]] || die "not confirmed; nothing changed"

    say "keeping the present state as $before"
    take_snapshot "$before"

    say "switching the subvolumes"
    sudo mv "$TOP/root" "$TOP/root.replaced-$ts" || die "could not rename the root subvolume; nothing changed"
    if ! sudo btrfs subvolume snapshot "$dir/root" "$TOP/root" >/dev/null; then
        sudo mv "$TOP/root.replaced-$ts" "$TOP/root"
        die "could not create the new root; the old one is back in place, nothing changed"
    fi
    if [[ -n $home ]]; then
        if ! { sudo mv "$TOP/home" "$TOP/home.replaced-$ts" &&
            sudo btrfs subvolume snapshot "$dir/home" "$TOP/home" >/dev/null; }; then
            sudo test -d "$TOP/home" || sudo mv "$TOP/home.replaced-$ts" "$TOP/home"
            sudo btrfs subvolume delete "$TOP/root" >/dev/null
            sudo mv "$TOP/root.replaced-$ts" "$TOP/root"
            die "could not switch home; root and home are back in place, nothing changed"
        fi
    fi

    say "rewriting $BOOT and the boot image"
    if ! restore_boot "$dir"; then
        echo "ERR: that failed; putting $BOOT, the boot image and the subvolumes back" >&2
        restore_boot "$TOP/$SNAPDIR/$before" || echo "ERR: $BOOT could not be put back either: restore it by hand from $SNAPDIR/$before/boot.tar before rebooting" >&2
        sudo btrfs subvolume delete "$TOP/root" >/dev/null
        sudo mv "$TOP/root.replaced-$ts" "$TOP/root"
        if [[ -n $home ]]; then
            sudo btrfs subvolume delete "$TOP/home" >/dev/null
            sudo mv "$TOP/home.replaced-$ts" "$TOP/home"
        fi
        exit 1
    fi
    sync

    say "done. Reboot now: sudo systemctl reboot"
    echo "Until the reboot you are still running the old system; what you change in it is"
    echo "left behind in root.replaced-$ts. After the reboot: $0 cleanup"
    echo "To undo this restore: $0 restore $before${home:+ --home}"
}

stage_cleanup() {
    local d sub answer running found=0
    open_top
    running=$(findmnt -no SOURCE / | sed -n 's/.*\[\/\(.*\)\]$/\1/p')
    for d in $(sudo sh -c "cd '$TOP' && ls -d root.replaced-* home.replaced-* 2>/dev/null" || true); do
        found=1
        if [[ $d == "$running" ]]; then
            echo "$d is the system that is running: reboot first"
            continue
        fi
        read -r -p "Delete $d for good? [y/N] " answer </dev/tty
        [[ $answer == [yY]* ]] || continue
        # Subvolumes created inside it (systemd makes some) have to go first, deepest first.
        for sub in $(sudo btrfs subvolume list -o "$TOP/$d" | sed -n 's/.* path //p' | sort -r); do
            sudo btrfs subvolume delete "$TOP/$sub" >/dev/null
        done
        sudo btrfs subvolume delete "$TOP/$d" >/dev/null && echo "deleted $d"
    done
    [[ $found == 1 ]] || echo "nothing to clean up"
}

stage_drop() {
    local name=${1:-} dir answer
    check_name "$name"
    open_top
    dir=$TOP/$SNAPDIR/$name
    sudo test -d "$dir" || die "no snapshot $name"
    read -r -p "Delete snapshot $name for good? [y/N] " answer </dev/tty
    [[ $answer == [yY]* ]] || die "kept"
    sudo test ! -d "$dir/root" || sudo btrfs subvolume delete "$dir/root" >/dev/null
    sudo test ! -d "$dir/home" || sudo btrfs subvolume delete "$dir/home" >/dev/null
    sudo rm -rf "$dir"
    echo "deleted snapshot $name"
}

stage_all() {
    stage_repo
    say "bluetooth"
    "$LAB/desktop/bt-sync.sh" || echo "WARN: no pairings taken over (see above); run '$0 bluetooth' again after pairing in macOS"
    say "snapshot of the clean system"
    stage_snapshot
    say "kernel"
    stage_kernel
    stage_tools
    say "all done. Reboot into the lab's kernel: sudo systemctl reboot"
    echo "Then: $KLAB/tbt-kernel.sh status, and a second snapshot if you like: $LAB/setup.sh snapshot lab-ready"
}

case ${1:-} in
all) stage_all ;;
repo) stage_repo ;;
bluetooth) stage_bluetooth ;;
snapshot) stage_snapshot "${2:-}" ;;
kernel) stage_kernel ;;
tools) stage_tools ;;
list) stage_list ;;
restore) stage_restore "${2:-}" "${3:-}" ;;
cleanup) stage_cleanup ;;
drop) stage_drop "${2:-}" ;;
*)
    echo "usage: $0 {all | repo | bluetooth | snapshot [NAME] | kernel | tools | list | restore NAME [--home] | cleanup | drop NAME}" >&2
    exit 2
    ;;
esac
