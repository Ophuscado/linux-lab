#!/usr/bin/env bash
# applekbd.sh: the lab's hid-apple (src-patches/linux/hid-apple) on the running kernel, without a reboot:
# Fn+F, Fn+C, Fn+P and Fn+D on an Apple keyboard send the Prog1 to Prog4 keys ("Launch (1)" to
# "Launch (4)" in KDE's shortcut settings), free to bind to window actions.
#
#   applekbd.sh build      apply the patch to the kernel tree and build the driver alone, as
#                          magicmouse.sh build does (same tree, same pinned commit)
#   applekbd.sh try        load it in place of the running driver, fn_shortcuts on, now and for
#                          the next boots
#   applekbd.sh undo       the kernel's own driver again
#   applekbd.sh show       which driver runs each Apple keyboard, and fn_shortcuts
#
# On a kernel built with the patch (tbt-kernel.sh), its own hid-apple has fn_shortcuts: try and
# undo set it now and at every boot (tmpfiles.d), with no driver beside it.
# Otherwise, when the kernel has hid-apple built in, the lab's is built as hid_apple_lab (HID driver
# "apple_lab") and try moves the keyboards over through sysfs, with a udev rule that does it
# again whenever the built-in driver takes one; a keyboard the lab driver refuses goes back to
# the built-in one at once. Then bind the four keys in System Settings > Keyboard > Shortcuts >
# KWin (the operator's choice, 18 Oct): Maximize Window Fn+F, Move Window to the Center Fn+C,
# Keep Window Above Others Fn+P, Keep Window on All Desktops Fn+D.

set -euo pipefail
REL=${APPLEKBD_REL:-$(uname -r)}
KCONFIG=${APPLEKBD_CONFIG:-/boot/config-$REL}
if [[ -z ${SRC:-} ]]; then
    UHOME=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6); UHOME=${UHOME:-$HOME}  # the invoking user's, also under sudo
    for SRC in "$(dirname "$(readlink -f "$0")")/../src/linux" "$UHOME/Projects/linux-asahi-tbt" "$UHOME/Projects/asahi-linux-tbt"; do [[ -e $SRC/.git ]] && break; done
fi
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$HERE/../src-patches/linux/hid-apple/0001-HID-apple-Optional-Fn-shortcuts-on-F-C-P-and-D.patch
UPD=/usr/lib/modules/$REL/updates
RULE=/etc/udev/rules.d/62-apple-lab.rules
OPTS=/etc/modprobe.d/hid_apple-lab.conf
LAB=$SRC/drivers/hid/lab-apple/hid-apple-lab.ko
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
builtin() { grep -q '^CONFIG_HID_APPLE=y' "$KCONFIG" 2>/dev/null; }
P=/sys/module/hid_apple/parameters
TMPF=/etc/tmpfiles.d/hid_apple-lab.conf
patched() { builtin && [[ -e $P/fn_shortcuts ]]; }
if builtin && ! patched; then MOD=hid_apple_lab; else MOD=hid_apple; fi

show() {
    local d
    echo "kernel: hid-apple $(if patched; then echo 'built in, with the patch'; elif builtin; then echo 'built in; the lab driver runs beside it as hid_apple_lab'; else echo 'is a module'; fi)"
    for d in /sys/bus/hid/drivers/apple/*:* /sys/bus/hid/drivers/apple_lab/*:*; do
        [[ -e $d ]] && echo "  ${d##*/}: ${d%/*}" | sed 's#/sys/bus/hid/drivers/##'
    done
    echo "fn_shortcuts: $(cat "/sys/module/$MOD/parameters/fn_shortcuts" 2>/dev/null || echo 'not in the running driver')"
    echo "udev rule: $([[ -f $RULE ]] && echo "$RULE" || echo none); options: $(grep -v '^#' "$OPTS" 2>/dev/null || echo none)"
}
# move DEVICE FROM TO: one HID device from one driver to the other, back to FROM if TO refuses it.
move() {
    echo "$1" | sudo tee "/sys/bus/hid/drivers/$2/unbind" >/dev/null
    echo "$1" | sudo tee "/sys/bus/hid/drivers/$3/bind" >/dev/null 2>&1 ||
        { echo "$1" | sudo tee "/sys/bus/hid/drivers/$2/bind" >/dev/null; echo "WARN: $3 did not take $1; it is back on $2" >&2; }
}

case ${1:-} in
build)
    # The tree, its commit check and the module-only build are magicmouse.sh's: one tree for both.
    [[ -e $SRC/.git ]] || die "no kernel tree; magicmouse.sh build makes it (the pinned commit, depth 1)"
    cd "$SRC"
    [[ -f .config ]] || die "$SRC has no configuration yet; run magicmouse.sh build first"
    if git apply --reverse --check "$PATCH" 2>/dev/null; then
        echo "the patch is in the tree already"
    else
        git apply --check "$PATCH" || die "the patch does not apply to $SRC"
        git apply "$PATCH"
    fi
    [[ $(make -s LOCALVERSION= kernelrelease) == "$REL" ]] || die "this tree makes release $(make -s LOCALVERSION= kernelrelease), the running kernel is $REL"
    if builtin; then
        mkdir -p drivers/hid/lab-apple
        sed 's/\.name = "apple",/.name = "apple_lab",/' drivers/hid/hid-apple.c >drivers/hid/lab-apple/hid-apple-lab.c
        grep -q '"apple_lab"' drivers/hid/lab-apple/hid-apple-lab.c || die "could not rename the HID driver in the copy"
        printf '%s\n' '# Written by applekbd.sh build: the lab driver beside a built-in one.' \
            'ccflags-y += -I$(srctree)/drivers/hid' 'obj-m += hid-apple-lab.o' >drivers/hid/lab-apple/Kbuild
        target=M=drivers/hid/lab-apple
    else
        target=drivers/hid/hid-apple.ko
    fi
    make -s LOCALVERSION= KBUILD_MODPOST_WARN=1 -j"$(nproc)" $target 2> >(grep -v -e ' undefined!$' \
        -e 'vmlinux.o is missing' -e 'may not have dependencies' -e 'many unresolved symbol' -e 'KBUILD_MODPOST_WARN=1' \
        -e 'proceed at your own risk' -e 'unresolved symbol warnings' -e 'Module.symvers is missing' >&2)
    builtin || LAB=$SRC/drivers/hid/hid-apple.ko
    [[ -f $LAB ]] || die "no $LAB after the build"
    echo "built: $LAB ($(modinfo -F vermagic "$LAB" 2>/dev/null))"
    ;;
try | undo)
    if patched; then
        v=$([[ $1 == try ]] && echo Y || echo N)
        echo "$v" | sudo tee "$P/fn_shortcuts" >/dev/null
        if [[ $v == Y ]]; then printf '%s\n' '# Written by applekbd.sh try; removed by applekbd.sh undo.' "w $P/fn_shortcuts - - - - Y" | sudo tee "$TMPF" >/dev/null
        else sudo rm -f "$TMPF"; fi
        show
        exit 0
    fi
    ;;&
try)
    builtin || LAB=$SRC/drivers/hid/hid-apple.ko
    [[ -f $LAB ]] || die "not built yet: applekbd.sh build"
    [[ $(modinfo -F vermagic "$LAB" | cut -d' ' -f1) == "$REL" ]] || die "$LAB is for $(modinfo -F vermagic "$LAB" | cut -d' ' -f1), not $REL"
    sudo mkdir -p "$UPD"
    sudo install -m 644 "$LAB" "$UPD/${LAB##*/}"
    sudo depmod -a "$REL"
    printf '%s\n' '# Written by applekbd.sh try; removed by applekbd.sh undo.' "options $MOD fn_shortcuts=1" | sudo tee "$OPTS" >/dev/null
    if builtin; then
        printf '%s\n' '# Written by applekbd.sh try; removed by applekbd.sh undo. Each keyboard the built-in' \
            '# driver takes goes to the lab driver, or back to the built-in one if that fails. A failure' \
            '# is marked in /run, so the two drivers do not take turns (gone at the next boot).' \
            'ACTION=="add|bind", SUBSYSTEM=="hid", DRIVER=="apple", RUN+="/bin/sh -c '"'"'[ -e /run/apple-lab.failed ] && exit 0; /sbin/modprobe hid_apple_lab || exit 0; echo %k > /sys/bus/hid/drivers/apple/unbind; echo %k > /sys/bus/hid/drivers/apple_lab/bind || { touch /run/apple-lab.failed; echo %k > /sys/bus/hid/drivers/apple/bind; }'"'"'"' |
            sudo tee "$RULE" >/dev/null
        sudo udevadm control --reload
        sudo modprobe hid_apple_lab || die "the lab driver did not load"
        for d in /sys/bus/hid/drivers/apple/*:*; do [[ -e $d ]] && move "${d##*/}" apple apple_lab; done
    else
        sudo modprobe -r hid_apple && sudo modprobe hid_apple || die "the driver did not load again; applekbd.sh undo"
    fi
    sleep 2
    show
    ;;
undo)
    sudo rm -f "$RULE" "$OPTS"
    sudo udevadm control --reload
    if builtin; then
        for d in /sys/bus/hid/drivers/apple_lab/*:*; do [[ -e $d ]] && move "${d##*/}" apple_lab apple; done
        sudo modprobe -r hid_apple_lab 2>/dev/null || true
        sudo rm -f "$UPD/hid-apple-lab.ko"
    else
        sudo rm -f "$UPD/hid-apple.ko"
        sudo depmod -a "$REL"
        sudo modprobe -r hid_apple && sudo modprobe hid_apple
    fi
    sudo depmod -a "$REL"
    show
    ;;
show) show ;;
*)
    echo "usage: $0 {build | try | undo | show}" >&2
    exit 2
    ;;
esac
