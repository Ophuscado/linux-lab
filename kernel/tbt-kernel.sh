#!/usr/bin/env bash
# tbt-kernel.sh: a kernel with Thunderbolt disks AND the GPU, installed next to the stock
# Fedora Asahi kernel. It is the stock kernel's own source (Asahi tag asahi-7.1.13-3) with
# the Apple USB4/Thunderbolt host driver of the Asahi 7.2 work-in-progress tree backported
# and this lab's PCIe tunneling on top (branch tbt/7.1 of github.com/Ophuscado/linux).
# The earlier trial kernel (7.2.2-tbtwip, branch tbt/pcie) had no GPU driver.
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
#             (see 'try' and 'stock')
#   try       makes Linux boot the trial kernel, with its device trees, until 'stock'
#   stock     makes Linux boot the stock kernel, with its device trees, until 'try'
#   status    prints what the running kernel sees, and whether kernel and device trees match
#   m1n1      only if status says the host DROM is rejected: replaces m1n1 1.6.1 with
#             Fedora's own 1.9.9 build (first release that writes the USB4 router ID)
#   cable N   debug: OR the bits N into the cable information the driver gives the router
#             firmware (0x10 = cable does 20 Gb/s per lane, 0 = off)
#   forget V  removes an older trial kernel, e.g.: forget 7.2.2-tbtwip
#   rollback  removes the kernel, restores stock device trees and m1n1 1.6.1
#   previous  puts back the kernel an install replaced (same release, kept in /var/lib/tbt-kernel/previous)
#             and boots it: from the stock kernel, when a rebuilt trial kernel does not come up
#   previous-dt   only the kept device trees, for the running kernel: when it booted but its trees are bad
#   dtb       only the device trees of the installed build, with TBT_OVERLAYS (e.g. TBT_OVERLAYS=t6022-ane): kernel
#             and modules stay; the boot image before is kept as boot.bin.previous
#
# The enclosures' udev rules and actions (authorize, read-only HFS+, spin-down, mount, bench,
# eject) are linux-lab's tbt-disks.sh; this script handles the kernel only.
#
# Kernel and device trees go together. The device trees are not loaded per boot entry:
# they are baked into m1n1/boot.bin on the EFI partition, one set for whatever kernel is
# picked afterwards. The stock 7.1 kernel hangs on the trial kernel's device trees, so
# 'try' and 'stock' always switch both, and each rewrites boot.bin. A copy of the original
# is kept as boot.bin.stock. Picking the other kernel by hand in the GRUB menu boots it on
# the wrong device trees.
#
# Since 29 Oct install also keeps the boot image it replaces as boot.bin.previous: copying that over boot.bin from
# macOS (below) brings back the device trees that booted before the install, for whatever kernel GRUB picks.
#
# If Linux no longer boots, pick the other kernel in the GRUB menu once (the trial kernel
# is expected to cope with stock device trees, not the other way round), then run 'try' or
# 'stock'. If that fails too, restore the stock boot image from macOS:
#   diskutil list                          # find the EFI partition next to the Linux one
#   sudo diskutil mount disk0sN
#   cp "/Volumes/<EFI name>/m1n1/boot.bin.stock" "/Volumes/<EFI name>/m1n1/boot.bin"
# and pick the stock kernel in the GRUB menu.
#
# Environment overrides: SRC (build directory), TBT_NO_GPU=1 (accept a build that lost
# the GPU driver; not expected any more), TBT_FORCE=1 (skip the machine and config
# guards), TBT_BASECFG (base kernel config; default is the stock kernel's),
# TBT_MAKE_ARGS (extra make arguments), TBT_SERIES (the extra series applied, below), TBT_OVERLAYS (device-tree
# overlays, below).

set -euo pipefail
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# The fork's branch: Asahi tag asahi-7.1.13-3 plus the backported USB4 stack and the
# changes kept as patches/ in this repository.
REPO=https://github.com/Ophuscado/linux
BRANCH=tbt/7.1
# Pinned so that what gets built is the tree this script was written against.
COMMIT=9d460b403164694c0f6a1a6ca1038d6a79dfc167
SUFFIX=-tbtwip
KEEP=/var/lib/tbt-kernel/previous
# The owner's kernel tree (18 Oct; before, ~/src/linux-asahi-tbt), named both
# ~/Projects/asahi-linux-tbt and ~/Projects/linux-asahi-tbt: the one that exists.
if [[ -z ${SRC:-} ]]; then
    for SRC in "$HOME/Projects/linux-lab/src/linux" "$HOME/Projects/linux-asahi-tbt" "$HOME/Projects/asahi-linux-tbt"; do [[ -d $SRC/.git ]] && break; done
fi
ESP_MNT=/run/tbt-esp
KOJI=https://kojipkgs.fedoraproject.org/packages/m1n1
M1N1_NEW=$KOJI/1.9.9/1.fc46/noarch/m1n1-1.9.9-1.fc46.noarch.rpm
M1N1_OLD=$KOJI/1.6.1/1.fc44/noarch/m1n1-1.6.1-1.fc44.noarch.rpm
DTB=arch/arm64/boot/dts/apple/t6022-j475d.dtb
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

# The lab's other kernel series (src-patches/linux/NAME, each based on a commit the pinned one contains), applied
# with git am on top of the pinned commit: TBT_SERIES, default the GPU's fdinfo and the two HID drivers;
# TBT_SERIES= builds the pinned commit alone.
SERIES=${TBT_SERIES-asahi-fdinfo hid-magicmouse hid-apple}
apply_series() {
    local s d
    for s in $SERIES; do
        d=$HERE/../src-patches/linux/$s
        compgen -G "$d/[0-9][0-9][0-9][0-9]-*.patch" >/dev/null || die "no series src-patches/linux/$s"
        if ! git -c user.name=tbt-kernel -c user.email=tbt-kernel@localhost am -q --3way "$d"/[0-9][0-9][0-9][0-9]-*.patch; then
            git am --abort || true
            die "series $s does not apply on ${COMMIT:0:12}; drop it with TBT_SERIES='${SERIES//$s/}'"
        fi
        echo "applied $s ($(compgen -G "$d/[0-9][0-9][0-9][0-9]-*.patch" | wc -l) patches)"
    done
}

# Device-tree overlays from the lab's linux-ane checkout (github.com/Ophuscado/linux-ane, packaging/dt), applied
# to the board's device tree after the build: TBT_OVERLAYS, default t6022-ane again since it booted with the fix
# (29 Oct; none between the panic and that boot; TBT_OVERLAYS= for none). t6022-ane adds
# the M2 Ultra's die-0 Neural Engine (a node only: its driver is loaded by hand, kernel/ane.sh) and, after it, this
# repository's kernel/dt/t6022-ane-dart-power.dts: with the overlay alone the kernel panicked at boot (29 Oct,
# SError in apple_dart_probe: a DART read with its power island off). An overlay is taken from kernel/dt/ first,
# then from src/linux-ane/packaging/dt/.
OVERLAYS=${TBT_OVERLAYS-t6022-ane}
[[ " $OVERLAYS " != *" t6022-ane "* || " $OVERLAYS " == *" t6022-ane-dart-power "* ]] || OVERLAYS="$OVERLAYS t6022-ane-dart-power"
# Properties whose phandle points at no node (dtc checks them on a compiled tree too: "Could not get phandle node").
# Not the __symbols__ paths: overlays record /soc/... for nodes under /soc@200000000, which dtc reports as missing
# paths while every phandle resolves (29 Oct, dtc 1.7.2: 16 such warnings, the DARTs at power-controller@260's 0x2c).
dangling() { scripts/dtc/dtc -I dtb -O dts -o /dev/null "$1" 2>&1 | tr -s '\n' | sed 's/Warning/\nWarning/g' |
    grep -v '__symbols__' | grep -c -i -E 'could not get phandle|bad phandle|invalid phandle' || true; }

apply_overlays() {
    local o src dtbo before after
    [[ -n $OVERLAYS ]] || return 0
    before=$(dangling "$DTB")
    for o in $OVERLAYS; do
        src=$HERE/dt/$o.dts
        [[ -f $src ]] || src=$HERE/../src/linux-ane/packaging/dt/$o.dts
        [[ -f $src ]] || die "no overlay $src (clone github.com/Ophuscado/linux-ane into src/linux-ane, or TBT_OVERLAYS=)"
        dtbo=$(mktemp --suffix=.dtbo)
        scripts/dtc/dtc -q -@ -I dts -O dtb -i "${src%/*}" -o "$dtbo" "$src" || die "overlay $o does not compile"
        scripts/dtc/fdtoverlay -i "$DTB" -o "$DTB.new" "$dtbo" || die "overlay $o does not apply to $DTB"
        mv "$DTB.new" "$DTB"; rm -f "$dtbo"
        echo "applied overlay $o to $DTB"
    done
    # An overlay that labels an existing node (omarchy-ane reaches AIC and the power controllers that way) must
    # keep that node's phandle: a libfdt older than dtc 1.7.1 gives it a new one and leaves every other user of the
    # node pointing at nothing (seen with dtc 1.7.0 on a test tree, 29 Oct).
    after=$(dangling "$DTB")
    ((after <= before)) || die "the overlays left $((after - before)) unresolved phandle references in $DTB (before: $before): this dtc's libfdt rewrites existing phandles"
    [[ " $OVERLAYS " != *" t6022-ane "* ]] || grep -q -a 'apple,t6022-ane' "$DTB" || die "the ANE node is not in $DTB after its overlay"
    if [[ " $OVERLAYS " == *" t6022-ane-dart-power "* ]]; then
        # Each ANE DART must point at the ANE_SYS power controller's own phandle (not a copy of the node).
        local dts ps n pd
        dts=$(scripts/dtc/dtc -q -I dtb -O dts "$DTB")
        ps=$(awk '/power-controller@260 \{/ { f = 1 } f && /phandle = / { gsub(/[<>;]/, ""); print $3; exit }' <<<"$dts")
        [[ -n $ps ]] || die "no phandle on power-controller@260 in $DTB"
        for n in 285800000 285810000 285820000; do
            pd=$(awk -v n="iommu@$n {" 'index($0, n) { f = 1 } f && /power-domains = / { gsub(/[<>;]/, ""); print $3; exit }' <<<"$dts")
            [[ $pd == "$ps" ]] || die "iommu@$n power-domains is ${pd:-missing}, power-controller@260 is $ps"
        done
        echo "the three ANE DARTs are in ANE_SYS (phandle $ps)"
    fi
}

# Switch an option on as a module unless the configuration already has it.
want() {
    case $(scripts/config -s "$1") in y | m) ;; *) scripts/config -m "$1" ;; esac
}

stage_build() {
    # Always from the stock kernel's configuration, also when a trial kernel is running:
    # an older trial build was configured without the GPU driver.
    local base=${TBT_BASECFG:-/boot/config-$(stock_kver)}
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
    apply_series

    say "configuring from $base"
    cp "$base" .config
    # Options that point at files only Fedora's own build provides are emptied.
    scripts/config --set-str LOCALVERSION "$SUFFIX" -d LOCALVERSION_AUTO \
        --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
        --set-str EFI_SBAT_FILE "" \
        -m USB4_APPLE_SOC -m RESET_APPLE_CIO
    # PCIe over Thunderbolt needs the Apple PCIe driver, and AHCI for the disks behind it.
    local s v was dropped=0
    # HFS+ (the enclosure's disks) sits behind the "miscellaneous filesystems" switch.
    scripts/config -e MISC_FILESYSTEMS
    for s in USB4 PCIE_APPLE ATA SATA_AHCI BLK_DEV_SD HFSPLUS_FS; do want "$s"; done
    mk olddefconfig

    for s in USB4_APPLE_SOC RESET_APPLE_CIO PCIE_APPLE SATA_AHCI BLK_DEV_SD HFSPLUS_FS; do
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

    # The 7.1 tree keeps the GPU driver. Should a build lose it anyway (the 7.2 tree marks
    # it BROKEN), the display would still work, rendered on the CPU: a visible change, so
    # it needs an explicit yes.
    was=$(scripts/config --file "$base" -s DRM_ASAHI)
    v=$(scripts/config -s DRM_ASAHI)
    if [[ $was == y || $was == m ]] && [[ $v != y && $v != m ]]; then
        echo "WARN: no GPU driver in this kernel (CONFIG_DRM_ASAHI did not survive the configuration)"
        [[ ${TBT_NO_GPU:-0} == 1 ]] ||
            die "rerun as: TBT_NO_GPU=1 $0 build   to accept a trial kernel without GPU acceleration"
    fi

    say "building with $(nproc) jobs"
    # Device-tree symbols, so overlays that name nodes by label (&aic, the power domains) apply.
    [[ -z $OVERLAYS ]] || export DTC_FLAGS=-@
    # The board tree is rebuilt every time: overlays are applied to it in place, and make would keep an
    # overlaid copy (newer than its sources) and apply them on top of it again.
    rm -f "$DTB"
    mk
    apply_overlays

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
    # The boot image as it is now (device trees of the kernel that boots today), for a restore from macOS when the new
    # one does not come up: boot.bin.stock alone made the stock kernel the only way back (29 Oct).
    esp_mount
    sudo cp --preserve=timestamps "$ESP_MNT/m1n1/boot.bin" "$ESP_MNT/m1n1/boot.bin.previous" && sudo sync
    echo "saved boot.bin.previous: $(bootbin_sha boot.bin.previous)"
    esp_umount
    # kernel-install below switches the device trees to the new kernel's. Afterwards the
    # mode found here is put back, kernel and device trees together.
    prev=$(dt_mode)
    echo "Linux boots the $prev kernel before install"

    # Installing over a release that is already there (the running trial kernel, rebuilt with more patches) would
    # leave no working copy of it: keep one, which 'previous' puts back from the stock kernel if the new one fails.
    if sudo test -f "/boot/vmlinuz-$v"; then
        say "keeping the installed $v in $KEEP (restore with: $0 previous)"
        sudo rm -rf "$KEEP"; sudo mkdir -p "$KEEP"
        sudo cp -a "/boot/vmlinuz-$v" "/boot/initramfs-$v.img" "$KEEP/" 2>/dev/null || true
        sudo cp -a "/boot/dtb-$v" "$KEEP/dtb" 2>/dev/null || true
        sudo tar -C /usr/lib/modules -cf "$KEEP/modules.tar" "$v"
        echo "$v" | sudo tee "$KEEP/release" >/dev/null
    fi
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

    say "result: Linux keeps booting the $prev kernel"
    set_mode "$prev"
    df -h /boot | tail -n 1
    if [[ $prev == trial ]]; then
        say "installed. Reboot to run it: sudo systemctl reboot"
    else
        say "installed. Next: $0 try"
    fi
}

# Put back the copy install kept of the release it replaced, then boot it as the trial kernel (run from the stock
# kernel when the newly built one does not come up).
stage_previous() {
    guard_machine
    sudo test -f "$KEEP/release" || die "no kept kernel in $KEEP"
    local v; v=$(sudo cat "$KEEP/release")
    say "restoring $v from $KEEP"
    sudo rm -rf "/usr/lib/modules/$v" && sudo tar -C /usr/lib/modules -xf "$KEEP/modules.tar"
    sudo cp -a "$KEEP/vmlinuz-$v" "$KEEP/initramfs-$v.img" /boot/
    sudo rm -rf "/boot/dtb-$v" && sudo cp -a "$KEEP/dtb" "/boot/dtb-$v"
    if command -v restorecon >/dev/null; then sudo restorecon -R "/usr/lib/modules/$v" /boot; fi
    set_mode trial
    say "the kept $v is back and Linux boots it. Reboot with: sudo systemctl reboot"
}

# Only the device trees: the kept copy's go back into /boot/dtb-<release> and boot.bin, the running kernel and its
# modules stay. For a kernel that booted, but whose device trees can panic the next boot (29 Oct: 1 boot in 11).
stage_previous_dt() {
    guard_machine
    sudo test -d "$KEEP/dtb" || die "no kept device trees in $KEEP"
    local v; v=$(kver)
    [[ $(sudo cat "$KEEP/release") == "$v" ]] || die "the kept device trees are for $(sudo cat "$KEEP/release"), not $v"
    sudo grep -q -a 'apple,t6022-ane' "$KEEP/dtb/apple/t6022-j475d.dtb" && die "the kept device trees have the ANE node too"
    say "device trees of $v back to the kept copy (no ANE node); kernel and modules unchanged"
    sudo rm -rf "/boot/dtb-$v" && sudo cp -a "$KEEP/dtb" "/boot/dtb-$v"
    if command -v restorecon >/dev/null; then sudo restorecon -R "/boot/dtb-$v"; fi
    set_mode trial
    say "the next boot uses them; nothing changes until then"
}

# Device trees only, for the installed kernel of this build: rebuild them, apply TBT_OVERLAYS, keep the current boot
# image as boot.bin.previous, put them in /boot/dtb-<release> and boot.bin. The kernel and its modules stay; the copy
# 'install' kept (previous, previous-dt) stays as it is.
stage_dtb() {
    guard_machine
    local v; v=$(kver)
    sudo test -f "/boot/vmlinuz-$v" || die "$v is not installed; run: $0 install"
    cd "$SRC"
    [[ -z $OVERLAYS ]] || export DTC_FLAGS=-@
    rm -f "$DTB"
    say "device trees of $v${OVERLAYS:+ with overlays:$OVERLAYS}"
    mk dtbs >/dev/null
    apply_overlays
    esp_mount
    sudo cp --preserve=timestamps "$ESP_MNT/m1n1/boot.bin" "$ESP_MNT/m1n1/boot.bin.previous" && sudo sync
    echo "saved boot.bin.previous: $(bootbin_sha boot.bin.previous)"
    esp_umount
    sudo install -D -m 0644 -t "/boot/dtb-$v/apple" arch/arm64/boot/dts/apple/*.dtb
    sudo install -D -m 0644 -t "/usr/lib/modules/$v/dtb/apple" arch/arm64/boot/dts/apple/*.dtb
    if command -v restorecon >/dev/null; then sudo restorecon -R "/boot/dtb-$v" "/usr/lib/modules/$v/dtb"; fi
    set_mode trial
    say "the next boot uses them. If it does not come up: from macOS, copy m1n1/boot.bin.previous over m1n1/boot.bin"
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
            for a in vendor_name device_name authorized generation unique_id; do
                [[ -r $d/$a ]] && printf ' %s=%s' "$a" "$(cat "$d/$a" 2>/dev/null)"
            done
            echo
        done
    else
        echo "no thunderbolt bus"
    fi
    echo "-- boltd: $(systemctl is-active bolt 2>/dev/null)"
    echo "-- usb"
    lsusb -t
    lsusb | grep -iE '174c|asmedia' || echo "no ASMedia USB device"
    echo "-- pci behind the thunderbolt ports (domains 0008 and up)"
    lspci -D -nn 2>/dev/null | grep -v '^0000:' || echo "none"
    echo "-- disks"
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
    # The boot image as it is now (device trees of the kernel that boots today), for a restore from macOS when the new
    # one does not come up: boot.bin.stock alone made the stock kernel the only way back (29 Oct).
    esp_mount
    sudo cp --preserve=timestamps "$ESP_MNT/m1n1/boot.bin" "$ESP_MNT/m1n1/boot.bin.previous" && sudo sync
    echo "saved boot.bin.previous: $(bootbin_sha boot.bin.previous)"
    esp_umount
    say "installing Fedora's m1n1 1.9.9 build"
    sudo dnf install -y "$M1N1_NEW"
    # The package trigger ignores failures of update-m1n1, so run it visibly as well.
    sudo update-m1n1
    echo "m1n1: $(rpm -q m1n1)"
    report_bootbin
    say "done. Next: $0 try"
}

# Remove an older trial kernel that is neither running nor the current build, then make
# sure the kernel Linux boots and the device trees still belong together.
stage_forget() {
    guard_machine
    local v=${1:-} mode
    [[ $v == *"$SUFFIX" ]] || die "usage: $0 forget <release ending in $SUFFIX>, e.g. 7.2.2$SUFFIX"
    [[ $(uname -r) != "$v" ]] || die "$v is running; boot another kernel first"
    [[ $v != "$(kver)" ]] || die "$v is the current build; rollback removes that one"
    mode=$(dt_mode)

    say "removing kernel $v"
    sudo kernel-install remove "$v" || true
    sudo rm -rf "/usr/lib/modules/$v" "/boot/dtb-$v"
    sudo rm -f "/boot/vmlinuz-$v" "/boot/initramfs-$v.img" "/boot/System.map-$v" "/boot/config-$v"

    say "Linux keeps booting the $mode kernel"
    set_mode "$mode"
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
cable) stage_cable "${2:-}" ;;
forget) stage_forget "${2:-}" ;;
rollback) stage_rollback "${2:-}" ;;
previous) stage_previous ;;
previous-dt) stage_previous_dt ;;
dtb) stage_dtb ;;
*)
    echo "usage: $0 {deps|build|install|try|stock|status|m1n1|cable [bits]|forget VERSION|rollback|previous|previous-dt|dtb}" >&2
    exit 2
    ;;
esac
