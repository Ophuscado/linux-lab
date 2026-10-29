#!/usr/bin/env bash
# magicmouse.sh: the lab's Magic Mouse driver (src-patches/linux/hid-magicmouse) on the running kernel, tried
# without a reboot.
#
#   magicmouse.sh build            apply the patch to the kernel tree (SRC, default
#                                  ~/Projects/asahi-linux-tbt, the tree tbt-kernel.sh builds,
#                                  else the one /usr/lib/modules/<release>/build points to) and
#                                  build drivers/hid/hid-magicmouse.ko there; "build --checkout"
#                                  first moves a tree at another commit to the running kernel's
#                                  (fetched at depth 1; refused with local changes). With no tree, it
#                                  fetches only the commit tbt-kernel.sh pins (depth 1, about
#                                  250 MB) and builds that one module against the running
#                                  kernel's configuration, not the whole kernel
#   magicmouse.sh try [HOLD_MS]    load it in place of the running driver: a resting finger
#                                  does not scroll for HOLD_MS (default 250) after the mouse
#                                  moved, a two-finger double tap zooms (Ctrl+=) and the next
#                                  one zooms back (Ctrl+0). Mouse and trackpad drop for a second
#   magicmouse.sh hold MS          the resting-finger guard of the running lab driver, now and
#                                  for the next load (0 turns it off)
#   magicmouse.sh speed N          scroll speed, 0 (slow) to 63 (fast; the kernel's default 32):
#                                  one scroll step per (64 - N) * 7 units of finger travel, so
#                                  1 needs 441, 22 needs 294 (two thirds), 32 needs 224. Set live on
#                                  every running driver and kept for the next boot and load
#   magicmouse.sh undo             the kernel's own driver again
#   magicmouse.sh show             which driver runs, its settings, whether the initramfs has one
#
# When the running kernel has the driver built in (CONFIG_HID_MAGICMOUSE=y, as 7.1.13-tbtwip:
# cell 81438), the lab's driver is built under another name, hid_magicmouse_lab (HID driver
# "magicmouse_lab"), and try moves the mice and trackpads over to it through sysfs (unbind
# from magicmouse, bind to magicmouse_lab); a udev rule does the same whenever the kernel's own
# binds one again (a reconnect, a boot), and puts it back if the lab's will not take it.
# Otherwise the module goes to /usr/lib/modules/<release>/updates/, which modprobe prefers over
# the kernel's own. After a reboot the driver that the initramfs holds (if it holds one) loads
# first: run try again, until a kernel built with the patch is installed (tbt-kernel.sh).
# The settings: /etc/tmpfiles.d/hid_magicmouse-lab.conf (scroll_hold_ms, smart_zoom), set
# again at every boot when the patched driver is the one loaded; linux-lab's ux-fix.sh keeps its own
# (emulate_3button, scroll_speed).

set -euo pipefail
# Overridable only so the build can be exercised off the target machine.
REL=${MAGICMOUSE_REL:-$(uname -r)}
KCONFIG=${MAGICMOUSE_CONFIG:-/boot/config-$REL}
# The operator's tree, named both ~/Projects/asahi-linux-tbt and ~/Projects/linux-asahi-tbt
# (18 Oct); the one that exists is used.
if [[ -z ${SRC:-} ]]; then
    for SRC in "$HOME/Projects/linux-lab/src/linux" "$HOME/Projects/linux-asahi-tbt" "$HOME/Projects/asahi-linux-tbt"; do [[ -d $SRC/.git ]] && break; done
fi
# Else the tree the running kernel was installed from (modules_install links it as build).
if [[ ! -d $SRC/.git ]] && b=$(readlink -f "/usr/lib/modules/$REL/build") && [[ -d $b/.git ]]; then SRC=$b; fi
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$HERE/../src-patches/linux/hid-magicmouse/0001-HID-magicmouse-no-scroll-from-a-resting-finger-smart-zoom.patch
UPD=/usr/lib/modules/$REL/updates
RULE=/etc/udev/rules.d/62-magicmouse-lab.rules
OPTS=/etc/modprobe.d/hid_magicmouse-lab.conf
LAB=$SRC/drivers/hid/lab/hid-magicmouse-lab.ko
LP=/sys/module/hid_magicmouse_lab/parameters
builtin() { grep -q '^CONFIG_HID_MAGICMOUSE=y' "$KCONFIG" 2>/dev/null; }
# The commit the running trial kernel was built from, as tbt-kernel.sh pins it.
KREPO=$(sed -n 's/^REPO=//p' "$HERE/tbt-kernel.sh")
KCOMMIT=$(sed -n 's/^COMMIT=//p' "$HERE/tbt-kernel.sh")
P=/sys/module/hid_magicmouse/parameters
TMPF=/etc/tmpfiles.d/hid_magicmouse-lab.conf
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

reload() {
    sudo modprobe -r hid_magicmouse || die "the driver did not unload"
    sudo modprobe hid_magicmouse || die "the driver did not load; magicmouse.sh undo"
}
show() {
    local d
    if builtin; then
        echo "kernel: the driver is built in; the lab's runs beside it as hid_magicmouse_lab"
        [[ -d $LP ]] && echo "lab driver: loaded (scroll_hold_ms $(cat $LP/scroll_hold_ms), smart_zoom $(cat $LP/smart_zoom), emulate_3button $(cat $LP/emulate_3button), scroll_speed $(cat $LP/scroll_speed))" || echo "lab driver: not loaded"
        for d in /sys/bus/hid/drivers/magicmouse/*:* /sys/bus/hid/drivers/magicmouse_lab/*:*; do
            [[ -e $d ]] && echo "  ${d##*/}: ${d%/*}" | sed 's#/sys/bus/hid/drivers/##'
        done
        echo "udev rule: $([[ -f $RULE ]] && echo "$RULE" || echo none)"
        return
    fi
    if [[ -e $P/scroll_hold_ms ]]; then
        echo "driver: the lab's (scroll_hold_ms $(cat $P/scroll_hold_ms), smart_zoom $(cat $P/smart_zoom), steps $(cat $P/smart_zoom_steps))"
    elif [[ -d $P ]]; then
        echo "driver: the kernel's own"
    else
        echo "driver: not loaded"
    fi
    echo "module modprobe picks: $(modinfo -n hid_magicmouse 2>/dev/null)"
    echo "initramfs of $REL: $(sudo lsinitrd "/boot/initramfs-$REL.img" 2>/dev/null | grep -c 'hid-magicmouse') hid-magicmouse file(s)"
    echo "settings at boot: $(cat "$TMPF" 2>/dev/null | grep -v '^#' | tr '\n' ' ' || true)"
}
# move DEVICE FROM TO: one HID device from one driver to the other, back to FROM if TO refuses it.
move() {
    echo "$1" | sudo tee "/sys/bus/hid/drivers/$2/unbind" >/dev/null
    echo "$1" | sudo tee "/sys/bus/hid/drivers/$3/bind" >/dev/null 2>&1 ||
        { echo "$1" | sudo tee "/sys/bus/hid/drivers/$2/bind" >/dev/null; echo "WARN: $3 did not take $1; it is back on $2" >&2; }
}

case ${1:-} in
build)
    if [[ ! -d $SRC/.git ]]; then
        [[ ! -e $SRC ]] || [[ -z $(ls -A "$SRC") ]] || die "$SRC exists and is not a git tree"
        echo "fetching ${KCOMMIT:0:12} of $KREPO into $SRC (depth 1)"
        mkdir -p "$SRC"
        git -C "$SRC" init -q
        git -C "$SRC" fetch -q --depth 1 "$KREPO" "$KCOMMIT" || die "the fetch failed; run build again (it starts over in the same folder)"
        git -C "$SRC" checkout -q --detach FETCH_HEAD
    fi
    cd "$SRC"
    # Without a finished build of its own, the tree must hold the running kernel's source before
    # anything is applied (cell 81430: a 6.14 tree, where the patch only failed to apply).
    if [[ ! -f .config || ! -f Module.symvers ]] && [[ $(git rev-parse HEAD) != "$KCOMMIT" ]]; then
        [[ ${2:-} == --checkout ]] ||
            die "$SRC is at $(git log -1 --format='%h %s' | cut -c1-70); the running kernel was built from ${KCOMMIT:0:12}. magicmouse.sh build --checkout fetches that commit (depth 1) and checks it out there; git -C $SRC checkout $(git rev-parse --short HEAD) goes back"
        [[ -z $(git status --porcelain --untracked-files=no) ]] || die "local changes in $SRC; commit or stash them first, nothing was touched"
        was=$(git rev-parse HEAD)
        git fetch -q --depth 1 "$KREPO" "$KCOMMIT" || die "the fetch of ${KCOMMIT:0:12} failed"
        git checkout -q --detach FETCH_HEAD
        echo "$SRC: checked out ${KCOMMIT:0:12}; it was at ${was:0:12} (git -C $SRC checkout $was goes back)"
    fi
    if git apply --reverse --check "$PATCH" 2>/dev/null; then
        echo "the patch is in the tree already"
    else
        git apply --check "$PATCH" || die "the patch does not apply to $SRC"
        git apply "$PATCH"
    fi
    if [[ -f .config && -f Module.symvers ]]; then
        make -s -j"$(nproc)" drivers/hid/hid-magicmouse.ko
    else
        # Only this module: the source of the running kernel and its configuration. Without a full
        # build there is no Module.symvers, so modpost only warns about the kernel's symbols; the
        # kernel has no CONFIG_MODVERSIONS to check them by (cell 81114, 18 Oct), and try refuses
        # a module whose release string differs.
        [[ -r $KCONFIG ]] || die "no $KCONFIG to build against"
        cp "$KCONFIG" .config
        make -s LOCALVERSION= olddefconfig
        diff -q <(grep '^CONFIG' "$KCONFIG") <(grep '^CONFIG' .config) >/dev/null ||
            echo "WARN: olddefconfig changed the configuration: $(diff <(grep '^CONFIG' "$KCONFIG") <(grep '^CONFIG' .config) | grep '^[<>]' | head -n 6 | tr '\n' ' ')"
        make -s LOCALVERSION= -j"$(nproc)" modules_prepare
        [[ $(make -s LOCALVERSION= kernelrelease) == "$REL" ]] || die "this tree makes release $(make -s LOCALVERSION= kernelrelease), the running kernel is $REL"
        target=drivers/hid/hid-magicmouse.ko
        if builtin; then
            # Built in, so compiled here it would be no module (cell 81438: "missing MODULE_LICENSE").
            mkdir -p drivers/hid/lab
            sed 's/\.name = "magicmouse",/.name = "magicmouse_lab",/' drivers/hid/hid-magicmouse.c >drivers/hid/lab/hid-magicmouse-lab.c
            grep -q '"magicmouse_lab"' drivers/hid/lab/hid-magicmouse-lab.c || die "could not rename the HID driver in the copy"
            printf '%s\n' '# Written by magicmouse.sh build: the lab driver beside a built-in one.' \
                'ccflags-y += -I$(srctree)/drivers/hid' 'obj-m += hid-magicmouse-lab.o' >drivers/hid/lab/Kbuild
            target=M=drivers/hid/lab
        fi
        make -s LOCALVERSION= KBUILD_MODPOST_WARN=1 -j"$(nproc)" $target 2> >(grep -v -e ' undefined!$' \
            -e 'vmlinux.o is missing' -e 'may not have dependencies' -e 'many unresolved symbol' -e 'KBUILD_MODPOST_WARN=1' \
            -e 'proceed at your own risk' -e 'unresolved symbol warnings' -e 'Module.symvers is missing' >&2)
        echo "module only: modpost had no symbol list of the kernel, its warnings about that are left out"
    fi
    if builtin; then
        [[ -f $LAB ]] || die "no $LAB after the build"
        echo "built: $LAB ($(modinfo -F vermagic "$LAB" 2>/dev/null))"
    else
        echo "built: $SRC/drivers/hid/hid-magicmouse.ko ($(modinfo -F vermagic drivers/hid/hid-magicmouse.ko 2>/dev/null))"
    fi
    ;;
try)
    hold=${2:-250}
    [[ $hold =~ ^[0-9]+$ ]] || die "HOLD_MS is a number of milliseconds"
    if builtin; then
        [[ -f $LAB ]] || die "not built yet: magicmouse.sh build"
        [[ $(modinfo -F vermagic "$LAB" | cut -d' ' -f1) == "$REL" ]] || die "$LAB is for $(modinfo -F vermagic "$LAB" | cut -d' ' -f1), not $REL"
        sudo mkdir -p "$UPD"
        sudo install -m 644 "$LAB" "$UPD/hid-magicmouse-lab.ko"
        sudo depmod -a "$REL"
        # The kernel driver's settings (linux-lab's ux-fix.sh) carry over to the lab's.
        echo "options hid_magicmouse_lab scroll_hold_ms=$hold smart_zoom=1 emulate_3button=$(cat $P/emulate_3button) scroll_speed=$(cat $P/scroll_speed)" | sudo tee "$OPTS" >/dev/null
        printf '%s\n' '# Written by magicmouse.sh try; removed by magicmouse.sh undo. Each mouse or trackpad the' \
            '# built-in driver takes goes to the lab driver, or back to the built-in one if that fails.' \
            '# A failure is marked in /run, so the two drivers do not take turns (gone at the next boot).' \
            'ACTION=="add|bind", SUBSYSTEM=="hid", DRIVER=="magicmouse", RUN+="/bin/sh -c '"'"'[ -e /run/magicmouse-lab.failed ] && exit 0; /sbin/modprobe hid_magicmouse_lab || exit 0; echo %k > /sys/bus/hid/drivers/magicmouse/unbind; echo %k > /sys/bus/hid/drivers/magicmouse_lab/bind || { touch /run/magicmouse-lab.failed; echo %k > /sys/bus/hid/drivers/magicmouse/bind; }'"'"'"' |
            sudo tee "$RULE" >/dev/null
        sudo udevadm control --reload
        sudo modprobe hid_magicmouse_lab || die "the lab driver did not load"
        for d in /sys/bus/hid/drivers/magicmouse/*:*; do [[ -e $d ]] && move "${d##*/}" magicmouse magicmouse_lab; done
        sleep 2
        show
        exit 0
    fi
    ko=$SRC/drivers/hid/hid-magicmouse.ko
    [[ -f $ko ]] || die "not built yet: magicmouse.sh build"
    [[ $(modinfo -F vermagic "$ko" | cut -d' ' -f1) == "$REL" ]] || die "$ko is for $(modinfo -F vermagic "$ko" | cut -d' ' -f1), not $REL"
    sudo mkdir -p "$UPD"
    sudo install -m 644 "$ko" "$UPD/hid-magicmouse.ko"
    sudo depmod -a "$REL"
    printf '%s\n' '# Written by magicmouse.sh try; removed by magicmouse.sh undo.' \
        "w $P/scroll_hold_ms - - - - $hold" "w $P/smart_zoom - - - - Y" | sudo tee "$TMPF" >/dev/null
    # smart_zoom is read when the mouse connects, so it goes in before the driver loads.
    echo "options hid_magicmouse scroll_hold_ms=$hold smart_zoom=1" | sudo tee /etc/modprobe.d/hid_magicmouse-lab.conf >/dev/null
    reload
    sleep 3
    show
    ;;
undo)
    if builtin; then
        sudo rm -f "$RULE" "$OPTS"
        sudo udevadm control --reload
        for d in /sys/bus/hid/drivers/magicmouse_lab/*:*; do [[ -e $d ]] && move "${d##*/}" magicmouse_lab magicmouse; done
        sudo modprobe -r hid_magicmouse_lab 2>/dev/null || true
        sudo rm -f "$UPD/hid-magicmouse-lab.ko"
        sudo depmod -a "$REL"
        show
        exit 0
    fi
    sudo rm -f "$UPD/hid-magicmouse.ko" "$TMPF" "$OPTS"
    sudo depmod -a "$REL"
    reload
    show
    ;;
hold)
    [[ ${2:-} =~ ^[0-9]+$ ]] || die "magicmouse.sh hold MS (e.g. 165; 0 is off)"
    if builtin; then p=$LP; o=hid_magicmouse_lab; else p=$P; o=hid_magicmouse; fi
    [[ -e $p/scroll_hold_ms ]] || die "the lab driver is not running: magicmouse.sh try"
    echo "$2" | sudo tee "$p/scroll_hold_ms" >/dev/null
    if [[ -f $OPTS ]]; then sudo sed -i -E "s/scroll_hold_ms=[0-9]+/scroll_hold_ms=$2/" "$OPTS"; fi
    if [[ -f $TMPF ]]; then sudo sed -i -E "s#(scroll_hold_ms - - - - )[0-9]+#\1$2#" "$TMPF"; fi
    echo "$o: scroll_hold_ms $(cat "$p/scroll_hold_ms")"
    ;;
speed)
    [[ ${2:-} =~ ^[0-9]+$ ]] && (($2 <= 63)) || die "magicmouse.sh speed N (0 slow to 63 fast; the kernel's default is 32)"
    for p in "$P" "$LP"; do [[ -e $p/scroll_speed ]] && echo "$2" | sudo tee "$p/scroll_speed" >/dev/null; done
    # Kept where each driver reads it: linux-lab's ux-fix.sh files for the kernel's, the lab's options.
    for f in "$OPTS" /etc/modprobe.d/hid_magicmouse.conf; do [[ -f $f ]] && sudo sed -i -E "s/scroll_speed=[0-9]+/scroll_speed=$2/" "$f"; done
    f=/etc/tmpfiles.d/hid_magicmouse.conf
    [[ -f $f ]] && sudo sed -i -E "s#(/scroll_speed - - - - )[0-9]+#\1$2#" "$f"
    for p in "$P" "$LP"; do [[ -e $p/scroll_speed ]] && echo "$(basename "$(dirname "$p")"): scroll_speed $(cat "$p/scroll_speed")"; done
    true
    ;;
show) show ;;
*)
    echo "usage: $0 {build | try [HOLD_MS] | hold MS | speed N | undo | show}" >&2
    exit 2
    ;;
esac
