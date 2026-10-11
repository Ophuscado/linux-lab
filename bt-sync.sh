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
# collected in macOS. Afterwards do not pair these devices in Linux again: a new pairing
# on either side replaces the key in the device, and the other system loses it.
#
# Only device names and addresses are shown, never keys. Old entries are kept, readable
# by root only, under /var/lib/bluetooth-old/.

set -euo pipefail

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

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
    mac=$(sed -n 's/.*(\([0-9A-F:]\{17\}\)) [A-Z/]*$/\1/p' <<<"$line")
    name=$(sed -n 's/^ID [0-9a-f:]* \(.*\) ([0-9A-F:]\{17\}) [A-Z/]*$/\1/p' <<<"$line")
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
    mac=$(sed -n 's/.*(\([0-9A-F:]\{17\}\)) [A-Z/]*$/\1/p' <<<"$line")
    [[ -n $mac && $seen != *" $mac "* ]] || continue
    seen+="$mac "
    state=$(bluetoothctl info "$mac" 2>/dev/null | grep -E 'Name:|Paired:|Connected:' | tr -s '\t\n' '  ' || true)
    echo "  $mac ${state:-not known to bluetoothd; try: sudo systemctl restart bluetooth}"
done <<<"$list"
echo
echo "A device that shows 'Connected: no' may just be asleep: press a key or click."
