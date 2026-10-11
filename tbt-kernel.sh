#!/usr/bin/env bash
# tbt-kernel.sh: trial of the Asahi 7.2 work-in-progress kernel, which carries the
# Apple USB4/Thunderbolt host driver, plus this lab's changes on top of it (branch
# tbt/pcie of github.com/Ophuscado/linux), installed next to the stock Fedora Asahi kernel.
#
# Written for: Apple Mac Studio (M2 Ultra, 2023), Fedora Asahi Remix 44,
# kernel 7.1.13-402.asahi.fc44.aarch64+16k, m1n1 1.6.1.
#
# Stages, in the order to run them, and what each one touches:
#   deps      dnf-installs the build packages
#   build     fetches the pinned commit and builds in $SRC only; nothing else on the
#             system changes. Run it again after updating this script: it moves $SRC to
#             the new pinned commit and rebuilds what changed
#   install   adds the kernel as an extra boot entry. What Linux boots stays as it was
#             (see 'try' and 'stock'). Also switches 'readonly' on
#   try       makes Linux boot the trial kernel, with its device trees, until 'stock'
#   stock     makes Linux boot the stock kernel, with its device trees, until 'try'
#   status    prints what the running kernel sees, and whether kernel and device trees match
#   m1n1      only if status says the host DROM is rejected: replaces m1n1 1.6.1 with
#             Fedora's own 1.9.9 build (first release that writes the USB4 router ID)
#   readonly  on|off: a udev rule that makes every disk reached through PCIe over
#             Thunderbolt read-only as it appears. On until you switch it off
#   mount     mounts every HFS+ volume on disks behind PCIe over Thunderbolt read-only
#             under /mnt/tbt/<volume name>; umount undoes it
#   bench     read-only speed test of those disks: N MiB (default 4096) from the start of
#             each, one at a time and then all at once
#   eject     run it BEFORE unplugging an enclosure whose disks came up through PCIe: it
#             refuses while one of them is mounted, then flushes and detaches the disks.
#             The enclosure's own PCI devices stay: taking those away makes the ASM2464
#             reconnect by itself 10 s later, with the disks attached again
#   cable N   debug: OR the bits N into the cable information the driver gives the router
#             firmware (0x10 = cable does 20 Gb/s per lane, 0 = off)
#   rollback  removes the kernel and the udev rule, restores stock device trees and
#             m1n1 1.6.1
#
# Kernel and device trees go together. The device trees are not loaded per boot entry:
# they are baked into m1n1/boot.bin on the EFI partition, one set for whatever kernel is
# picked afterwards. The stock 7.1 kernel hangs on the trial kernel's device trees, so
# 'try' and 'stock' always switch both, and each rewrites boot.bin. A copy of the original
# is kept as boot.bin.stock. Picking the other kernel by hand in the GRUB menu boots it on
# the wrong device trees.
#
# If Linux no longer boots, pick the other kernel in the GRUB menu once (the trial kernel
# is expected to cope with stock device trees, not the other way round), then run 'try' or
# 'stock'. If that fails too, restore the stock boot image from macOS:
#   diskutil list                          # find the EFI partition next to the Linux one
#   sudo diskutil mount disk0sN
#   cp "/Volumes/<EFI name>/m1n1/boot.bin.stock" "/Volumes/<EFI name>/m1n1/boot.bin"
# and pick the stock kernel in the GRUB menu.
#
# The trial kernel has no GPU acceleration: the pinned branch disables the GPU driver.
# The build stage therefore only proceeds with TBT_NO_GPU=1.
#
# Environment overrides: SRC (build directory), TBT_NO_GPU=1 (accept the missing GPU
# driver), TBT_FORCE=1 (skip the machine and config guards), TBT_BASECFG (base kernel
# config), TBT_MAKE_ARGS (extra make arguments).

set -euo pipefail

# The lab's branch: AsahiLinux/linux asahi-wip-7.2 at 236788cd2602 plus the commits that
# are also kept as patches/ in the lab repository.
REPO=https://github.com/Ophuscado/linux
BRANCH=tbt/pcie
# Pinned so that what gets built is the tree this script was written against.
COMMIT=523466d61f0b1a7afc3ab36fb0c58b1e6dcfa1f7
SUFFIX=-tbtwip
SRC=${SRC:-$HOME/src/linux-asahi-tbt}
ESP_MNT=/run/tbt-esp
KOJI=https://kojipkgs.fedoraproject.org/packages/m1n1
M1N1_NEW=$KOJI/1.9.9/1.fc46/noarch/m1n1-1.9.9-1.fc46.noarch.rpm
M1N1_OLD=$KOJI/1.6.1/1.fc44/noarch/m1n1-1.6.1-1.fc44.noarch.rpm
DTB=arch/arm64/boot/dts/apple/t6022-j475d.dtb
RO_RULE=/etc/udev/rules.d/00-tbt-readonly.rules
MNT=/mnt/tbt
# Overridable only so the stages can be exercised off the target machine.
DT=${TBT_DT:-/proc/device-tree}

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

# LOCALVERSION= keeps the release string independent of git state, so every make
# invocation (build, modules_install) agrees on the same version.
mk() {
    # shellcheck disable=SC2086
    make LOCALVERSION= -j"$(nproc)" ${TBT_MAKE_ARGS:-} "$@"
}

guard_machine() {
    [[ ${TBT_FORCE:-0} == 1 ]] && return 0
    [[ $(uname -m) == aarch64 ]] || die "not aarch64"
    local model
    model=$(tr -d '\0' <"$DT/model" 2>/dev/null || true)
    [[ $model == "Apple Mac Studio (M2 Ultra, 2023)" ]] ||
        die "written for the M2 Ultra Mac Studio, this is '$model' (TBT_FORCE=1 to override)"
}

kver() {
    [[ -f $SRC/include/config/kernel.release ]] || die "no build found in $SRC; run: $0 build"
    local v
    v=$(<"$SRC/include/config/kernel.release")
    [[ $v == *"$SUFFIX" ]] || die "unexpected kernel release '$v' (expected a $SUFFIX suffix)"
    printf '%s' "$v"
}

esp_mount() {
    local uuid
    uuid=$(tr -d '\0' <"$DT/chosen/asahi,efi-system-partition" 2>/dev/null || true)
    [[ -n $uuid ]] || die "cannot identify the EFI partition from the device tree"
    sudo mkdir -p "$ESP_MNT"
    mountpoint -q "$ESP_MNT" || sudo mount "PARTUUID=$uuid" "$ESP_MNT"
    # Checked as root: if the partition is also mounted at /boot/efi, this mount shares
    # its restrictive umask and a normal user cannot see inside it.
    if ! sudo test -f "$ESP_MNT/m1n1/boot.bin"; then
        echo "EFI partition PARTUUID=$uuid mounted at $ESP_MNT contains:" >&2
        sudo ls -la "$ESP_MNT" "$ESP_MNT/m1n1" >&2 || true
        findmnt -n -o SOURCE,TARGET,OPTIONS "$ESP_MNT" >&2 || true
        die "no m1n1/boot.bin on the EFI partition"
    fi
}

esp_umount() {
    if mountpoint -q "$ESP_MNT"; then sudo umount "$ESP_MNT"; fi
}

# A stage that stops early must not leave the EFI partition mounted.
trap 'esp_umount || true' EXIT

bootbin_sha() { sudo sha256sum "$ESP_MNT/m1n1/$1" | cut -d' ' -f1; }

# Keep the first, pristine boot.bin; later runs must not overwrite it with a modified one.
backup_bootbin() {
    esp_mount
    if sudo test -f "$ESP_MNT/m1n1/boot.bin.stock"; then
        echo "boot.bin.stock already present: $(bootbin_sha boot.bin.stock)"
    else
        sudo cp --preserve=timestamps "$ESP_MNT/m1n1/boot.bin" "$ESP_MNT/m1n1/boot.bin.stock"
        sudo sync
        [[ $(bootbin_sha boot.bin) == "$(bootbin_sha boot.bin.stock)" ]] ||
            die "backup of boot.bin does not match the original"
        echo "saved boot.bin.stock: $(bootbin_sha boot.bin.stock) at $(date -Is)"
    fi
    esp_umount
}

report_bootbin() {
    esp_mount
    echo "boot.bin        $(bootbin_sha boot.bin)"
    if sudo test -f "$ESP_MNT/m1n1/boot.bin.stock"; then
        echo "boot.bin.stock  $(bootbin_sha boot.bin.stock)"
    fi
    # 0 means the stock device trees, anything else the trial ones.
    echo "USB4 markers in boot.bin: $(sudo grep -c -a 'apple,t6020-usb4-acio' "$ESP_MNT/m1n1/boot.bin" || true)"
    esp_umount
}

# Release of the newest installed kernel that is not the trial one.
stock_kver() {
    local d v best=
    for d in /boot/dtb-*; do
        v=${d#/boot/dtb-}
        [[ -d $d && $v != *"$SUFFIX" ]] || continue
        sudo test -f "/boot/vmlinuz-$v" || continue
        best=$(printf '%s\n%s\n' "$best" "$v" | sort -V | tail -n 1)
    done
    [[ -n $best ]] || die "no stock kernel with device trees found under /boot"
    printf '%s' "$best"
}

# Which kernel the device trees in the boot image belong to: trial or stock.
dt_mode() {
    if [[ $(readlink /boot/dtb) == *"$SUFFIX" ]]; then echo trial; else echo stock; fi
}

# Make Linux boot one kernel on its own device trees: $1 is trial or stock.
set_mode() {
    local v
    if [[ $1 == trial ]]; then v=$(kver); else v=$(stock_kver); fi
    sudo test -f "/boot/vmlinuz-$v" || die "/boot/vmlinuz-$v is missing; run: $0 install"
    [[ -d /boot/dtb-$v ]] || die "/boot/dtb-$v is missing; run: $0 install"

    backup_bootbin
    sudo ln -sfn "dtb-$v" /boot/dtb
    # Rebuilds boot.bin from m1n1, the device trees /boot/dtb points at, and U-Boot.
    sudo update-m1n1
    sudo grubby --set-default "/boot/vmlinuz-$v"
    sudo grub2-editenv - unset next_entry

    echo "default kernel: $(sudo grubby --default-kernel)"
    echo "/boot/dtb -> $(readlink /boot/dtb)"
    report_bootbin
}

stage_deps() {
    say "installing build packages"
    sudo dnf install -y git-core gcc make bc bison flex perl-interpreter openssl openssl-devel \
        elfutils-libelf-devel dwarves rust rust-src rustfmt bindgen-cli clang python3 \
        grubby kmod zstd xz pciutils
}

# Move $SRC to the pinned commit. Earlier versions of this script patched two files in
# place; that change is part of the branch now, so it is set aside (kept as a diff) and
# dropped. Any other local change stops the stage.
checkout_pinned() {
    local dirty f keep
    dirty=$(git status --porcelain --untracked-files=no | awk '{print $2}')
    for f in $dirty; do
        case $f in
        drivers/thunderbolt/apple.c | drivers/usb/typec/tipd/core.c) ;;
        *) die "local change in $SRC/$f; commit it or move it away, it will not be overwritten" ;;
        esac
    done
    if [[ -n $dirty ]]; then
        keep=$SRC/local-changes-$(date +%Y%m%d-%H%M%S).diff
        # shellcheck disable=SC2086
        git diff -- $dirty >"$keep"
        # shellcheck disable=SC2086
        git checkout -q -- $dirty
        echo "the in-place patch of an earlier script version was saved as $keep and dropped"
    fi
    git checkout -q --detach "$COMMIT"
}

# Switch an option on as a module unless the configuration already has it.
want() {
    case $(scripts/config -s "$1") in y | m) ;; *) scripts/config -m "$1" ;; esac
}

stage_build() {
    local base=${TBT_BASECFG:-/boot/config-$(uname -r)}
    [[ -r $base ]] || die "cannot read base config $base"

    say "fetching $BRANCH at ${COMMIT:0:12} into $SRC"
    mkdir -p "$SRC"
    cd "$SRC"
    [[ -d .git ]] || git init -q
    if ! git cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
        git fetch --depth 1 "$REPO" "$COMMIT" ||
            die "pinned commit is no longer fetchable from $REPO; the branch was rewritten"
    fi
    checkout_pinned

    say "configuring from $base"
    cp "$base" .config
    # Options that point at files only Fedora's own build provides are emptied.
    scripts/config --set-str LOCALVERSION "$SUFFIX" -d LOCALVERSION_AUTO \
        --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
        --set-str EFI_SBAT_FILE "" \
        -m USB4_APPLE_SOC -m RESET_APPLE_CIO
    # PCIe over Thunderbolt needs the Apple PCIe driver, and AHCI for the disks behind it.
    local s v was dropped=0
    for s in USB4 PCIE_APPLE ATA SATA_AHCI BLK_DEV_SD HFSPLUS_FS; do want "$s"; done
    mk olddefconfig

    for s in USB4_APPLE_SOC RESET_APPLE_CIO PCIE_APPLE SATA_AHCI BLK_DEV_SD; do
        v=$(scripts/config -s "$s")
        [[ $v == y || $v == m ]] || die "CONFIG_$s did not survive olddefconfig (got '$v')"
    done
    # The PCIe driver follows the Thunderbolt core: built in only if that is built in.
    was=$(scripts/config --file "$base" -s PCIE_APPLE)
    v=$(scripts/config -s PCIE_APPLE)
    [[ $was != y || $v == y ]] ||
        echo "WARN: CONFIG_PCIE_APPLE was built in and is now a module (CONFIG_USB4 is a module)"
    scripts/diffconfig "$base" .config >config.diff 2>/dev/null || true

    # Options this machine depends on must not be dropped silently by the version jump.
    for s in RUST DRM_APPLE APPLE_DART NVME_APPLE PHY_APPLE_ATC TYPEC_TPS6598X USB_DWC3_APPLE \
        PINCTRL_APPLE_GPIO APPLE_RTKIT APPLE_SART; do
        was=$(scripts/config --file "$base" -s "$s")
        v=$(scripts/config -s "$s")
        if [[ $was == y || $was == m ]] && [[ $v != y && $v != m ]]; then
            echo "WARN: CONFIG_$s was '$was' in the base config and is now '$v'"
            dropped=1
        fi
    done
    if [[ $dropped == 1 && ${TBT_FORCE:-0} != 1 ]]; then
        mk rustavailable || true
        die "required options were dropped (see WARN lines above); not building"
    fi

    # The pinned branch marks the GPU driver as BROKEN (commit 97b22d135, "Mark the driver
    # broken as long as it is"), so this kernel has no GPU acceleration: the display still
    # works through the display controller driver, rendered on the CPU. That is a visible
    # change, so it needs an explicit yes.
    was=$(scripts/config --file "$base" -s DRM_ASAHI)
    v=$(scripts/config -s DRM_ASAHI)
    if [[ $was == y || $was == m ]] && [[ $v != y && $v != m ]]; then
        echo "WARN: no GPU driver in this kernel (CONFIG_DRM_ASAHI is disabled upstream on this branch)"
        [[ ${TBT_NO_GPU:-0} == 1 ]] ||
            die "rerun as: TBT_NO_GPU=1 $0 build   to accept a trial kernel without GPU acceleration"
    fi

    say "building with $(nproc) jobs"
    mk

    local img
    img=$(mk -s image_name)
    [[ -f $img ]] || die "kernel image $img missing"
    [[ -f $DTB ]] || die "$DTB missing"
    grep -q -a 'apple,t6020-usb4-acio' "$DTB" || die "device tree has no USB4 nodes"
    grep -q -a 'apple,t8103-usb4-pcie' "$DTB" || die "device tree has no Thunderbolt PCIe nodes"
    [[ $(scripts/config -s USB4_APPLE_SOC) == y || -f drivers/thunderbolt/thunderbolt_apple.ko ]] ||
        die "thunderbolt_apple.ko missing"
    say "built $(kver) ($img). Nothing outside $SRC was changed. Next: $0 install"
}

stage_install() {
    guard_machine
    local v img mod prev stage
    v=$(kver)
    mod=/usr/lib/modules/$v
    stage=$SRC/_stage
    cd "$SRC"
    img=$(mk -s image_name)
    # GRUB on arm64 needs an EFI image; a gzip'd Image is not one, the plain Image is.
    [[ $img == *.gz ]] && img=arch/arm64/boot/Image
    [[ -f $img ]] || die "kernel image $img missing; run: $0 build"

    say "staging modules (as the current user)"
    rm -rf "$stage"
    mk INSTALL_MOD_PATH="$stage" INSTALL_MOD_STRIP=1 modules_install >/dev/null
    [[ -d $stage/lib/modules/$v ]] || die "modules were not staged for $v"

    say "backing up the boot image"
    backup_bootbin
    # kernel-install below switches the device trees to the new kernel's. Afterwards the
    # mode found here is put back, kernel and device trees together.
    prev=$(dt_mode)
    echo "Linux boots the $prev kernel before install"

    say "installing $v"
    sudo rm -rf "$mod"
    sudo cp -a --no-preserve=ownership "$stage/lib/modules/$v" "$mod"
    sudo install -D -m 0644 -t "$mod/dtb/apple" arch/arm64/boot/dts/apple/*.dtb
    sudo install -m 0755 "$img" "$mod/vmlinuz"
    sudo install -m 0644 System.map "$mod/System.map"
    sudo install -m 0644 .config "$mod/config"
    if command -v restorecon >/dev/null; then sudo restorecon -R "$mod"; fi
    sudo kernel-install add "$v" "$mod/vmlinuz"

    sudo test -f "/boot/vmlinuz-$v" || die "/boot/vmlinuz-$v missing after kernel-install"
    sudo test -f "/boot/initramfs-$v.img" || die "/boot/initramfs-$v.img missing after kernel-install"

    stage_readonly on

    say "result: Linux keeps booting the $prev kernel"
    set_mode "$prev"
    df -h /boot | tail -n 1
    if [[ $prev == trial ]]; then
        say "installed. Reboot to run it: sudo systemctl reboot"
    else
        say "installed. Next: $0 try"
    fi
}

stage_try() {
    guard_machine
    say "switching Linux to the trial kernel and its device trees"
    set_mode trial
    say "Linux now boots $(kver) until you run: $0 stock"
    echo "Reboot with: sudo systemctl reboot. After it boots: $0 status"
    echo "If it does not come up, see 'If Linux no longer boots' at the top of this script."
}

stage_stock() {
    guard_machine
    say "switching Linux to the stock kernel and its device trees"
    set_mode stock
    say "Linux now boots $(stock_kver) until you run: $0 try"
    echo "Reboot with: sudo systemctl reboot"
}

stage_status() {
    local d log
    local def
    def=$(sudo grubby --default-kernel)
    echo "kernel: $(uname -r)"
    echo "m1n1:   $(rpm -q m1n1)"
    echo "boots:  $def on $(dt_mode) device trees (/boot/dtb -> $(readlink /boot/dtb))"
    echo "grub:   $(sudo grub2-editenv list | grep -E 'next_entry' || echo 'next_entry not set')"
    if [[ $def == *"$(readlink /boot/dtb | sed 's/^dtb-//')" ]]; then
        echo "        kernel and device trees match"
    else
        echo "WARN:   the default kernel does not match the device trees; the next boot may"
        echo "        hang. Run: $0 try   or   $0 stock"
    fi
    echo "-- modules"
    lsmod | grep -E '^(thunderbolt|thunderbolt_apple|reset_apple_cio|phy_apple_atc|tps6598x) ' || true
    echo "-- thunderbolt bus"
    if [[ -d /sys/bus/thunderbolt/devices ]]; then
        for d in /sys/bus/thunderbolt/devices/*; do
            [[ -e $d ]] || continue
            printf '%s' "$(basename "$d")"
            for a in vendor_name device_name authorized generation; do
                [[ -r $d/$a ]] && printf ' %s=%s' "$a" "$(cat "$d/$a" 2>/dev/null)"
            done
            echo
        done
    else
        echo "no thunderbolt bus"
    fi
    echo "-- usb"
    lsusb -t
    lsusb | grep -iE '174c|asmedia' || echo "no ASMedia USB device"
    echo "-- pci behind the thunderbolt ports (domains 0008 and up)"
    lspci -D -nn 2>/dev/null | grep -v '^0000:' || echo "none"
    echo "-- disks (read-only rule: $([[ -f $RO_RULE ]] && echo on || echo off))"
    lsblk -o NAME,TRAN,RO,SIZE,MODEL
    echo "-- kernel log"
    log=$(sudo dmesg | grep -iE 'thunderbolt|usb4|acio|nhi|drom|atcphy|phy-apple-atc|tunnel|cio|pcie-apple|pci 00(0[89a-f]|1)|pcieport 00(0[89a-f]|1)|ahci|ata[0-9]+|sd [0-9]' || true)
    echo "$log" | tail -n 140
    echo "-- reading"
    if grep -qiE 'No valid host DROM|DROM UID CRC8 mismatch' <<<"$log"; then
        echo "The host DROM from m1n1 $(rpm -q --qf '%{VERSION}' m1n1) is rejected. Next: $0 m1n1, then $0 try"
    elif [[ $(uname -r) != *"$SUFFIX" ]]; then
        echo "This is not the trial kernel. Run: $0 try, reboot, then $0 status"
    fi
}

stage_m1n1() {
    guard_machine
    say "backing up the boot image"
    backup_bootbin
    say "installing Fedora's m1n1 1.9.9 build"
    sudo dnf install -y "$M1N1_NEW"
    # The package trigger ignores failures of update-m1n1, so run it visibly as well.
    sudo update-m1n1
    echo "m1n1: $(rpm -q m1n1)"
    report_bootbin
    say "done. Next: $0 try"
}

stage_rollback() {
    guard_machine
    local v=${1:-}
    [[ -n $v ]] || v=$(kver)
    [[ $v == *"$SUFFIX" ]] || die "refusing to remove '$v': not a $SUFFIX kernel"
    [[ $(uname -r) != "$v" ]] || die "boot the stock kernel first ($0 stock, reboot), then run rollback"

    say "removing kernel $v"
    sudo kernel-install remove "$v" || true
    sudo rm -rf "/usr/lib/modules/$v" "/boot/dtb-$v"
    sudo rm -f "/boot/vmlinuz-$v" "/boot/initramfs-$v.img" "/boot/System.map-$v" "/boot/config-$v"
    sudo grub2-editenv - unset next_entry
    stage_readonly off

    if [[ $(rpm -q --qf '%{VERSION}' m1n1) != 1.6.1 ]]; then
        say "restoring m1n1 1.6.1"
        sudo dnf -y downgrade m1n1 || sudo dnf install -y "$M1N1_OLD"
    fi
    sudo update-m1n1

    say "result"
    echo "m1n1: $(rpm -q m1n1)"
    echo "default kernel: $(sudo grubby --default-kernel)"
    echo "/boot/dtb -> $(readlink /boot/dtb)"
    report_bootbin
    echo "boot.bin and boot.bin.stock should now have the same checksum."
}

# Disks behind PCIe over Thunderbolt appear under one of the six tunneled controllers,
# whose device names all end in 30000000.pcie (the internal one is 580000000.pcie). The
# rule runs before any other udev program gets to act on a new disk or partition.
stage_readonly() {
    case ${1:-} in
    on)
        printf '%s\n' \
            '# Written by tbt-kernel.sh readonly on; removed by readonly off and by rollback.' \
            'ACTION=="add|change", SUBSYSTEM=="block", DEVPATH=="*30000000.pcie/*", RUN+="/usr/sbin/blockdev --setro /dev/%k"' |
            sudo tee "$RO_RULE" >/dev/null
        sudo udevadm control --reload
        echo "read-only rule is on: disks behind PCIe over Thunderbolt appear read-only"
        ;;
    off)
        sudo rm -f "$RO_RULE"
        sudo udevadm control --reload
        echo "read-only rule is off. Disks already present stay read-only until they are"
        echo "replugged, or: sudo blockdev --setrw /dev/sdX"
        ;;
    *) die "usage: $0 readonly on|off" ;;
    esac
}

# Names (sda, sdb, ...) of the disks reached through PCIe over Thunderbolt.
tunnel_disks() {
    local disk
    for disk in /sys/block/sd*; do
        [[ -e $disk ]] || continue
        [[ $(readlink -f "$disk") == *30000000.pcie/* ]] && echo "${disk##*/}"
    done
    return 0
}

stage_mount() {
    local d part fstype label dir n=0
    sudo modprobe hfsplus 2>/dev/null ||
        echo "WARN: no hfsplus module for this kernel; run build and install again, then reboot"
    for d in $(tunnel_disks); do
        for part in $(lsblk -lnp -o NAME,TYPE "/dev/$d" | awk '$2 == "part" {print $1}'); do
            fstype=$(lsblk -n -o FSTYPE "$part")
            [[ $fstype == hfsplus ]] || continue
            if findmnt -n "$part" >/dev/null; then
                continue
            fi
            label=$(lsblk -n -o LABEL "$part" | tr -c 'A-Za-z0-9._\n-' '_')
            dir=$MNT/${label:-${part##*/}}
            # Two volumes with the same name must not end up on top of each other.
            if mountpoint -q "$dir" 2>/dev/null; then dir=$dir-${part##*/}; fi
            sudo mkdir -p "$dir"
            if sudo mount -t hfsplus -o ro "$part" "$dir"; then n=$((n + 1)); fi
        done
    done
    echo "mounted $n volume(s) read-only"
    findmnt -t hfsplus -o TARGET,SOURCE,SIZE,USED,OPTIONS || true
    echo "Files keep their macOS owner (usually uid 501): read private folders with sudo."
}

stage_umount() {
    local src
    for src in $(findmnt -t hfsplus -n -o SOURCE); do
        [[ " $(tunnel_disks | tr '\n' ' ') " == *" $(lsblk -n -o PKNAME "$src") "* ]] || continue
        sudo umount "$src" && echo "unmounted $src"
    done
}

# Reads only. The first read wakes a disk that is spun down, so it is not timed.
stage_bench() {
    local mib=${1:-4096} d disks
    disks=$(tunnel_disks)
    [[ -n $disks ]] || die "no disks behind PCIe over Thunderbolt"
    for d in $disks; do sudo dd if="/dev/$d" of=/dev/null bs=1M count=1 iflag=direct status=none; done
    say "one disk at a time, $mib MiB each"
    for d in $disks; do
        printf '%s: ' "$d"
        sudo dd if="/dev/$d" of=/dev/null bs=4M count=$((mib / 4)) iflag=direct 2>&1 | tail -n 1
    done
    say "all disks at once, $mib MiB each"
    for d in $disks; do
        (sudo dd if="/dev/$d" of=/dev/null bs=4M count=$((mib / 4)) iflag=direct 2>&1 |
            tail -n 1 | sed "s/^/$d: /") &
    done
    wait
}

# The disks are flushed and removed from the system while they can still answer; the SATA
# controller and the bridges of the enclosure stay bound, which keeps the enclosure quiet.
stage_eject() {
    local d mounted=0 found=0
    for d in $(tunnel_disks); do
        if lsblk -n -o MOUNTPOINTS "/dev/$d" | grep -q .; then
            echo "/dev/$d is mounted:"
            lsblk -o NAME,SIZE,MOUNTPOINTS "/dev/$d"
            mounted=1
        fi
    done
    [[ $mounted == 0 ]] || die "unmount these first ($0 umount), then run eject again"

    sync
    for d in $(tunnel_disks); do
        found=1
        echo "detaching /dev/$d"
        echo 1 | sudo tee "/sys/block/$d/device/delete" >/dev/null
    done
    if [[ $found == 1 ]]; then
        echo "done: the enclosure can be unplugged now"
    else
        echo "no disks are attached through PCIe over Thunderbolt"
    fi
}

stage_cable() {
    local p=/sys/module/thunderbolt_apple/parameters/cable_info_or
    [[ -e $p ]] || die "no cable_info_or parameter; boot the trial kernel with an enclosure plugged in"
    echo "${1:-0x10}" | sudo tee "$p" >/dev/null
    echo "cable_info_or is now $(cat "$p") (16 = 20 Gb/s per lane, 0 = off)."
    echo "It applies to the next plug-in: unplug the enclosure and plug it back in."
}

case ${1:-} in
deps) stage_deps ;;
build) stage_build ;;
install) stage_install ;;
try) stage_try ;;
stock) stage_stock ;;
status) stage_status ;;
m1n1) stage_m1n1 ;;
readonly) stage_readonly "${2:-}" ;;
mount) stage_mount ;;
umount) stage_umount ;;
bench) stage_bench "${2:-}" ;;
eject) stage_eject ;;
cable) stage_cable "${2:-}" ;;
rollback) stage_rollback "${2:-}" ;;
*)
    echo "usage: $0 {deps|build|install|try|stock|status|mount|umount|bench [MiB]|eject|m1n1|readonly on|off|cable [bits]|rollback}" >&2
    exit 2
    ;;
esac
