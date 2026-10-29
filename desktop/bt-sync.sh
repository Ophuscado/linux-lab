#!/usr/bin/env bash
# bt-sync.sh: let Linux use the Bluetooth pairings that macOS made, so keyboard, mouse and
# trackpad work in both systems without pairing again.
#
# How it works: macOS keeps the pairing keys of its devices in the Mac's NVRAM, and
# asahi-btsync (part of Fedora Asahi) copies them into BlueZ. It never touches a device
# that Linux already has an entry for, though, and that is the usual problem: an old
# Linux pairing with a key the device has since replaced. This script finds those, asks,
# sets the old entry aside and lets asahi-btsync write the macOS one.
#
# When to run it: in Linux, after the devices were (re)paired in macOS. Nothing has to be
# collected in macOS. "bt-sync.sh status" shows what both sides know, without keys.
# "bt-sync.sh names" gives each device Linux shows only by its address a name: the one macOS
# stored, else the Apple product its Modalias names (the product IDs of the kernel's hid-ids.h).
# The operator, 18 Oct: keyboard and trackpad showed their addresses; macOS's list held only the
# mouse. It is BlueZ's own alias, kept in its info file, set over D-Bus.
# Afterwards do not pair these devices in Linux again: a new pairing
# on either side replaces the key in the device, and the other system loses it.
#
# Only device names and addresses are shown, never keys. Old entries are kept, readable
# by root only, under /var/lib/bluetooth-old/.

set -euo pipefail

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
# asahi-btsync's list format has changed between versions: take any line with an address.
mac_of() { grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' <<<"$1" | head -n 1 | tr 'a-f' 'A-F' || true; }
name_of() { sed -E 's/^ID [0-9A-Fa-f]+:[0-9A-Fa-f]+ +//; s/ *\(?([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\)?.*$//' <<<"$1"; }

# status: what Linux knows about each device, without keys.
if [[ ${1:-} == status ]]; then
    echo "asahi-btsync: $(rpm -q asahi-btsync 2>/dev/null || echo 'not installed')"
    echo "adapter: $(bluetoothctl show 2>/dev/null | grep -E 'Powered|Pairable|Discoverable:' | tr -s '\t\n' '  ')"
    echo "-- what macOS stored (asahi-btsync list, as printed)"
    sudo asahi-btsync list 2>&1 || true
    echo "-- what bluetoothd has"
    while IFS= read -r line; do
        mac=$(mac_of "$line")
        [[ -n $mac ]] || continue
        printf '%s %s\n' "$mac" "$(bluetoothctl info "$mac" 2>/dev/null | grep -E 'Name:|Paired:|Bonded:|Trusted:|Connected:' | tr -s '\t\n' '  ')"
    done < <(bluetoothctl devices 2>/dev/null)
    echo "-- entries on disk (name, kind of key, written)"
    sudo find /var/lib/bluetooth -mindepth 2 -maxdepth 2 -type d | while read -r d; do
        printf '%s: %s / %s / %s\n' "$(basename "$d")" \
            "$(sudo sed -n 's/^Name=//p' "$d/info" 2>/dev/null)" \
            "$(sudo grep -oE '^\[(LinkKey|LongTermKey|PeripheralLongTermKey|IdentityResolvingKey)\]' "$d/info" 2>/dev/null | tr -d '[]' | tr '\n' ' ')" \
            "$(sudo stat -c %y "$d/info" 2>/dev/null | cut -c1-16)"
    done
    echo "-- bluetooth messages of this boot (last 40)"
    sudo journalctl -b --no-pager -o short-monotonic -u bluetooth -k 2>/dev/null | grep -iE 'bluetooth|hci0|bluez' | tail -n 40
    exit 0
fi

# apple_name PRODUCT: the product an Apple Bluetooth device's Modalias product ID stands for.
apple_name() {
    case ${1,,} in
    0269 | 030d | 0323) echo "Magic Mouse" ;;
    030e | 0265 | 0324) echo "Magic Trackpad" ;;
    0267 | 029c | 0320) echo "Magic Keyboard" ;;
    026c | 029f | 0322) echo "Magic Keyboard with Numeric Keypad" ;;
    029a | 0321) echo "Magic Keyboard with Touch ID" ;;
    022c | 022d | 022e | 0239 | 023a | 023b | 0255 | 0256 | 0257) echo "Apple Wireless Keyboard" ;;
    esac
}
alias_set() {
    busctl --system set-property org.bluez "/org/bluez/$hci/dev_${1//:/_}" org.bluez.Device1 Alias s "$2" &&
        echo "  $1: named $2" || echo "  $1: not known to bluetoothd, not named"
}
# names: the alias of every device whose name Linux does not know.
if [[ ${1:-} == names ]]; then
    list=$(sudo asahi-btsync list) || die "asahi-btsync could not read the NVRAM"
    hci=
    for d in /sys/class/bluetooth/hci[0-9]*; do [[ -e $d ]] && { hci=${d##*/}; break; }; done
    [[ -n $hci ]] || die "no Bluetooth adapter"
    seen=" "
    while IFS= read -r line; do
        mac=$(mac_of "$line")
        name=$(name_of "$line")
        [[ -n $mac && -n $name && $seen != *" $mac "* ]] || continue
        seen+="$mac "
        if bluetoothctl info "$mac" 2>/dev/null | grep -q '^\s*Name:'; then
            echo "  $mac: Linux knows its name ($(bluetoothctl info "$mac" | sed -n 's/^\s*Name: //p'))"
            continue
        fi
        alias_set "$mac" "$name"
    done <<<"$list"
    # The ones macOS did not store: the product their Modalias says (usb:v004Cp0265d...: Apple).
    while IFS= read -r line; do
        mac=$(mac_of "$line")
        [[ -n $mac && $seen != *" $mac "* ]] || continue
        seen+="$mac "
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        grep -q '^\s*Name:' <<<"$info" && continue
        m=$(sed -nE 's/^\s*Modalias: (usb|bluetooth):v004Cp([0-9A-Fa-f]{4}).*/\2/p' <<<"$info")
        name=$(apple_name "$m")
        if [[ -n $name ]]; then alias_set "$mac" "$name"; else echo "  $mac: no name and not an Apple product this script knows ($(sed -n 's/^\s*Modalias: //p' <<<"$info"))"; fi
    done < <(bluetoothctl devices 2>/dev/null)
    exit 0
fi

command -v asahi-btsync >/dev/null || sudo dnf install -y asahi-btsync
command -v bluetoothctl >/dev/null || die "bluetoothctl not found"
sudo -v || exit 1

list=$(sudo asahi-btsync list) || die "asahi-btsync could not read the NVRAM"
[[ -n $list ]] || die "macOS has stored no Bluetooth pairings in the NVRAM. Pair the devices in macOS first."

keep=/var/lib/bluetooth-old/$(date +%Y%m%d-%H%M%S)
replace=()

# The list is read on descriptor 3 so the question below can use the terminal.
echo "Devices macOS has paired:"
seen=" "
while IFS= read -r -u 3 line; do
    mac=$(mac_of "$line")
    name=$(name_of "$line")
    [[ -n $mac && $seen != *" $mac "* ]] || continue
    seen+="$mac "
    entry=$(sudo sh -c "ls -d /var/lib/bluetooth/*/$mac 2>/dev/null | head -n 1")
    if [[ -z $entry ]] || ! sudo test -f "$entry/info"; then
        echo "  $name ($mac): not known to Linux yet, will be added"
    elif bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'; then
        echo "  $name ($mac): connected in Linux right now, left alone"
    else
        echo "  $name ($mac): Linux has its own pairing and the device is not connected"
        read -r -p "      Replace the Linux pairing with the one from macOS? [y/N] " answer </dev/tty
        if [[ $answer == [yY]* ]]; then replace+=("$mac|$entry"); fi
    fi
done 3<<<"$list"

for item in "${replace[@]}"; do
    mac=${item%%|*}
    entry=${item#*|}
    sudo install -d -m 0700 "$keep"
    sudo cp -a "$entry" "$keep/"
    bluetoothctl remove "$mac" >/dev/null 2>&1 || true
    sudo rm -rf "$entry"
    echo "old Linux pairing of $mac kept in $keep"
done

echo
echo "Copying the pairings from macOS:"
# Prints one line per device it adds, tells bluetoothd to reload and connects them. It
# also reports failure when a device it added is asleep and does not answer, so a failure
# here is judged by the state printed below, not on its own.
sudo asahi-btsync sync || echo "asahi-btsync reported a failure; see the state below"
sleep 3

echo
echo "State now:"
seen=" "
while IFS= read -r line; do
    mac=$(mac_of "$line")
    [[ -n $mac && $seen != *" $mac "* ]] || continue
    seen+="$mac "
    state=$(bluetoothctl info "$mac" 2>/dev/null | grep -E 'Name:|Paired:|Connected:' | tr -s '\t\n' '  ' || true)
    echo "  $mac ${state:-not known to bluetoothd; try: sudo systemctl restart bluetooth}"
done <<<"$list"
echo
echo "A device that shows 'Connected: no' may just be asleep: press a key or click."
