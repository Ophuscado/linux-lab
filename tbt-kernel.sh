#!/usr/bin/env bash
# tbt-kernel.sh: trial of the Asahi 7.2 work-in-progress kernel, which carries the
# Apple USB4/Thunderbolt host driver, installed next to the stock Fedora Asahi kernel.
#
# Written for: Apple Mac Studio (M2 Ultra, 2023), Fedora Asahi Remix 44,
# kernel 7.1.13-402.asahi.fc44.aarch64+16k, m1n1 1.6.1.
#
# Stages, in the order to run them, and what each one touches:
#   deps      dnf-installs the build packages
#   build     clones and builds in $SRC only; nothing else on the system changes
#   install   adds the kernel as an extra boot entry and keeps the stock kernel as default.
#             Rewrites m1n1/boot.bin on the EFI partition, because the device trees in it
#             are shared by every installed kernel. A copy is kept as boot.bin.stock.
#   try       selects the new kernel for the NEXT BOOT ONLY; a power cycle returns to stock
#   status    run after booting the new kernel; prints what it sees
#   m1n1      only if status says the host DROM is rejected: replaces m1n1 1.6.1 with
#             Fedora's own 1.9.9 build (first release that writes the USB4 router ID)
#   patch     fixes the Thunderbolt driver's cable-speed check, makes the port fall back
#             to USB 3 properly when a device gives up on USB4, and adds a debug parameter
#             (cable_info_or); then rebuilds. Follow with install, try and a reboot
#   cable N   on the patched kernel: OR the bits N into the cable information the driver
#             gives the router firmware (0x10 = cable does 20 Gb/s per lane, 0 = off)
#   rollback  removes the kernel, restores stock device trees and m1n1 1.6.1
#
# If Linux no longer boots at all (not expected), restore the boot image from macOS:
#   diskutil list                          # find the EFI partition next to the Linux one
#   sudo diskutil mount disk0sN
#   cp "/Volumes/<EFI name>/m1n1/boot.bin.stock" "/Volumes/<EFI name>/m1n1/boot.bin"
#
# The trial kernel has no GPU acceleration: the pinned branch disables the GPU driver.
# The build stage therefore only proceeds with TBT_NO_GPU=1.
#
# Environment overrides: SRC (build directory), TBT_NO_GPU=1 (accept the missing GPU
# driver), TBT_FORCE=1 (skip the machine and config guards), TBT_BASECFG (base kernel
# config), TBT_MAKE_ARGS (extra make arguments).

set -euo pipefail

REPO=https://github.com/AsahiLinux/linux
BRANCH=asahi-wip-7.2
# Pinned so that what gets built is the tree that was inspected, not whatever the branch is today.
COMMIT=236788cd2602a24c703fe7bdaddaf73ef77d2027
SUFFIX=-tbtwip
SRC=${SRC:-$HOME/src/linux-asahi-tbt}
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

stage_deps() {
    say "installing build packages"
    sudo dnf install -y git-core gcc make bc bison flex perl-interpreter openssl openssl-devel \
        elfutils-libelf-devel dwarves rust rust-src rustfmt bindgen-cli clang python3 \
        grubby kmod zstd xz
}

stage_build() {
    local base=${TBT_BASECFG:-/boot/config-$(uname -r)}
    [[ -r $base ]] || die "cannot read base config $base"

    say "fetching $BRANCH at ${COMMIT:0:12} into $SRC"
    mkdir -p "$SRC"
    cd "$SRC"
    if [[ ! -d .git ]]; then
        git init -q
        git remote add origin "$REPO"
    fi
    if ! git cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
        git fetch --depth 1 origin "$COMMIT" ||
            die "pinned commit is no longer fetchable; the branch was rewritten, ask before using its new tip"
    fi
    git checkout -q --detach "$COMMIT"

    say "configuring from $base"
    cp "$base" .config
    # Options that point at files only Fedora's own build provides are emptied.
    scripts/config --set-str LOCALVERSION "$SUFFIX" -d LOCALVERSION_AUTO \
        --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
        --set-str EFI_SBAT_FILE "" \
        -m USB4_APPLE_SOC -m RESET_APPLE_CIO
    case $(scripts/config -s USB4) in y | m) ;; *) scripts/config -m USB4 ;; esac
    mk olddefconfig

    local s v was dropped=0
    for s in USB4_APPLE_SOC RESET_APPLE_CIO; do
        v=$(scripts/config -s "$s")
        [[ $v == y || $v == m ]] || die "CONFIG_$s did not survive olddefconfig (got '$v')"
    done
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
    prev=$(sudo grubby --default-kernel)
    echo "default kernel before install: $prev"

    say "installing $v"
    sudo rm -rf "$mod"
    sudo cp -a --no-preserve=ownership "$stage/lib/modules/$v" "$mod"
    sudo install -D -m 0644 -t "$mod/dtb/apple" arch/arm64/boot/dts/apple/*.dtb
    sudo install -m 0755 "$img" "$mod/vmlinuz"
    sudo install -m 0644 System.map "$mod/System.map"
    sudo install -m 0644 .config "$mod/config"
    if command -v restorecon >/dev/null; then sudo restorecon -R "$mod"; fi
    sudo kernel-install add "$v" "$mod/vmlinuz"

    # The stock kernel stays the default; the new one is only ever booted through 'try'.
    sudo grubby --set-default "$prev"

    say "result"
    sudo test -f "/boot/vmlinuz-$v" || die "/boot/vmlinuz-$v missing after kernel-install"
    sudo test -f "/boot/initramfs-$v.img" || die "/boot/initramfs-$v.img missing after kernel-install"
    echo "default kernel: $(sudo grubby --default-kernel)"
    echo "/boot/dtb -> $(readlink /boot/dtb)"
    report_bootbin
    df -h /boot | tail -n 1
    say "installed. Next: $0 try"
}

stage_try() {
    guard_machine
    local v entry
    v=$(kver)
    entry=$(sudo sh -c "ls /boot/loader/entries/*-$v.conf 2>/dev/null" | head -n 1 || true)
    [[ -n $entry ]] || die "no boot entry for $v; run: $0 install"
    entry=$(basename "$entry" .conf)
    sudo grub2-reboot "$entry"
    sudo grub2-editenv list | grep -E 'next_entry|saved_entry' || true
    say "the next boot only will use $v. Reboot with: sudo systemctl reboot"
    echo "If it does not come up, power-cycle: the stock kernel boots again."
    echo "After it boots: $0 status"
}

stage_status() {
    local d log
    echo "kernel: $(uname -r)"
    echo "m1n1:   $(rpm -q m1n1)"
    echo "grub:   $(sudo grub2-editenv list | grep -E 'next_entry' || echo 'next_entry not set')"
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
    echo "-- disks"
    lsblk -o NAME,TRAN,SIZE,MODEL
    echo "-- kernel log"
    log=$(sudo dmesg | grep -iE 'thunderbolt|usb4|acio|nhi|drom|atcphy|phy-apple-atc|tunnel|cio' || true)
    echo "$log" | tail -n 80
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
    [[ $(uname -r) != "$v" ]] || die "boot the stock kernel first (power-cycle), then run rollback"

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

# The driver derives the cable information word from what the port controller reports.
# It set the 20 Gb/s-per-lane flag only for a cable speed of exactly 3 (USB4 Gen 3). The
# cables here report 4 (USB4 v2), so the flag was missing, the Mac's router trained at
# 10 Gb/s per lane against an enclosure at 20, and the link never came up. The patch
# accepts any speed of 3 or above, and adds a run-time override (cable_info_or) for tests.
#
# Second change, in the port-controller driver: these enclosures only tunnel PCIe, which
# this kernel cannot serve, so after 10 s they drop USB4 and fall back to USB 3 without
# an unplug. The USB controller was not reinitialised for that, which left the port with
# USB 2 only (and the enclosure reporting no medium). The patch takes the USB controller
# down and up again whenever a partner enters or leaves USB4/Thunderbolt.
write_patch() {
    cat >"$1" <<'PATCH_EOF'
diff --git a/drivers/thunderbolt/apple.c b/drivers/thunderbolt/apple.c
index 530008cc8..94f3d7960 100644
--- a/drivers/thunderbolt/apple.c
+++ b/drivers/thunderbolt/apple.c
@@ -140,6 +140,11 @@
 #define TB_VSE_CAP_APPLE_CABLE_INFO_LEGACY_ADAPTER BIT(9)
 #define TB_VSE_CAP_APPLE_CABLE_INFO_TBT2_3 BIT(10)
 
+static unsigned int cable_info_or;
+module_param(cable_info_or, uint, 0644);
+MODULE_PARM_DESC(cable_info_or,
+		 "Debug: bits OR-ed into the cable information word of a present cable");
+
 /**
  * struct apple_cio - Apple Converged I/O host router complex
  * @dev: ACIO device
@@ -843,7 +848,11 @@ static int apple_cio_tbt_switch_set(struct typec_thunderbolt_switch_dev *sw,
 		acio->target_cable_info = TB_VSE_CAP_APPLE_CABLE_INFO_PRESENT;
 		if (FIELD_GET(EUDO_CABLE_TYPE_MASK, data->usb4.eudo) != EUDO_CABLE_TYPE_PASSIVE)
 			acio->target_cable_info |= TB_VSE_CAP_APPLE_CABLE_INFO_ACTIVE_CABLE;
-		if (FIELD_GET(EUDO_CABLE_SPEED_MASK, data->usb4.eudo) == EUDO_CABLE_SPEED_USB4_GEN3)
+		/*
+		 * Cables rated above Gen 3 (USB4 v2 cables report speed 4) also
+		 * carry 20 Gb/s per lane, which is the most this router does.
+		 */
+		if (FIELD_GET(EUDO_CABLE_SPEED_MASK, data->usb4.eudo) >= EUDO_CABLE_SPEED_USB4_GEN3)
 			acio->target_cable_info |= TB_VSE_CAP_APPLE_CABLE_INFO_20_GBPS;
 		if (data->orientation == TYPEC_ORIENTATION_REVERSE)
 			acio->target_cable_info |= TB_VSE_CAP_APPLE_CABLE_INFO_ORIENTATION_REVERSE;
@@ -852,6 +861,14 @@ static int apple_cio_tbt_switch_set(struct typec_thunderbolt_switch_dev *sw,
 		break;
 	}
 
+	/* Debug aid: lets cable-information bits be tested without rebuilding. */
+	if (acio->target_cable_info && cable_info_or) {
+		dev_info(acio->dev, "cable info 0x%x overridden to 0x%x\n",
+			 acio->target_cable_info,
+			 acio->target_cable_info | cable_info_or);
+		acio->target_cable_info |= cable_info_or;
+	}
+
 	if (acio->target_cable_info == acio->current_cable_info)
 		return 0;
 
diff --git a/drivers/usb/typec/tipd/core.c b/drivers/usb/typec/tipd/core.c
index 0687cc28d..18e65f9a6 100644
--- a/drivers/usb/typec/tipd/core.c
+++ b/drivers/usb/typec/tipd/core.c
@@ -662,6 +662,15 @@ static void cd321x_typec_update_mode(struct tps6598x *tps, struct cd321x_status
 	cd321x->state.data = NULL;
 }
 
+/* True while the port is in a tunneled mode, i.e. USB4 or the Thunderbolt alternate mode. */
+static bool cd321x_state_is_tunneled(const struct cd321x *cd321x)
+{
+	if (!cd321x->state.alt)
+		return cd321x->state.mode == TYPEC_MODE_USB4;
+
+	return cd321x->state.alt == cd321x->port_altmode_tbt;
+}
+
 static void cd321x_update_work(struct work_struct *work)
 {
 	struct cd321x *cd321x = container_of(to_delayed_work(work),
@@ -684,6 +693,11 @@ static void cd321x_update_work(struct work_struct *work)
 	bool usb_connection = st.data_status &
 			      (TPS_DATA_STATUS_USB2_CONNECTION | TPS_DATA_STATUS_USB3_CONNECTION);
 
+	bool was_tunneled = cd321x_state_is_tunneled(cd321x);
+	bool is_tunneled = new_connected &&
+			   (st.data_status & (TPS_DATA_STATUS_TBT_CONNECTION |
+					      CD321X_DATA_STATUS_USB4_CONNECTION));
+
 	enum usb_role old_role = usb_role_switch_get_role(tps->role_sw);
 	enum usb_role new_role = USB_ROLE_NONE;
 	enum typec_pwr_opmode pwr_opmode = TYPEC_PWR_MODE_USB;
@@ -708,8 +722,15 @@ static void cd321x_update_work(struct work_struct *work)
 		 (is_pd && memcmp(&st.partner_identity,
 				  &cd321x->cur_partner_identity, sizeof(struct usb_pd_identity))));
 
-	/* If we are switching from an active role, transition to USB_ROLE_NONE first */
-	if (old_role != USB_ROLE_NONE && (new_role != old_role || was_disconnected))
+	/*
+	 * If we are switching from an active role, transition to USB_ROLE_NONE first.
+	 * The same is needed when a partner enters or leaves USB4/Thunderbolt without a
+	 * disconnect, e.g. a device that gives up on USB4 and falls back to USB3: the PHY
+	 * can only change mode while the USB controller is down, otherwise the port is
+	 * left with USB2 only.
+	 */
+	if (old_role != USB_ROLE_NONE &&
+	    (new_role != old_role || was_disconnected || was_tunneled != is_tunneled))
 		usb_role_switch_set_role(tps->role_sw, USB_ROLE_NONE);
 
 	/* Process partner disconnection or change */
PATCH_EOF
}

stage_patch() {
    kver >/dev/null
    cd "$SRC"
    local pf
    pf=$(mktemp)
    write_patch "$pf"
    if git apply --reverse --check "$pf" 2>/dev/null; then
        echo "patch already applied"
    else
        # An earlier version of this patch may be in the tree; start from the pinned file.
        git checkout -q -- drivers/thunderbolt/apple.c drivers/usb/typec/tipd/core.c
        git apply --check "$pf" || die "patch does not apply to $SRC"
        git apply "$pf"
        echo "patch applied to drivers/thunderbolt/apple.c and drivers/usb/typec/tipd/core.c"
    fi
    rm -f "$pf"
    say "rebuilding"
    mk
    say "rebuilt $(kver). Next: $0 install, then $0 try, and reboot"
}

stage_cable() {
    local p=/sys/module/thunderbolt_apple/parameters/cable_info_or
    [[ -e $p ]] || die "this kernel's driver has no cable_info_or parameter; run: $0 patch, install, try, then reboot"
    echo "${1:-0x10}" | sudo tee "$p" >/dev/null
    echo "cable_info_or is now $(cat "$p") (16 = 20 Gb/s per lane, 0 = off)."
    echo "It applies to the next plug-in: unplug the enclosure and plug it back in."
}

case ${1:-} in
deps) stage_deps ;;
build) stage_build ;;
install) stage_install ;;
try) stage_try ;;
status) stage_status ;;
m1n1) stage_m1n1 ;;
patch) stage_patch ;;
cable) stage_cable "${2:-}" ;;
rollback) stage_rollback "${2:-}" ;;
*)
    echo "usage: $0 {deps|build|install|try|status|m1n1|patch|cable [bits]|rollback}" >&2
    exit 2
    ;;
esac
