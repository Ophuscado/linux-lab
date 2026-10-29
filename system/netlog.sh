#!/usr/bin/env bash
# netlog.sh: send the kernel messages of this Mac to a second computer as they happen, so
# that a freeze still leaves its last lines somewhere. Uses the kernel's netconsole (UDP).
#
#   On the second computer (macOS or Linux), first:   ./netlog.sh listen
#       prints its address, then writes everything received to ~/netlog-<time>.txt
#   On the Mac under test (Linux):                    ./netlog.sh on ADDRESS
#       then, to see that it works:                   ./netlog.sh test
#       and when done:                                ./netlog.sh off
#
# Both computers must be on the same network, and the Mac under test should use Ethernet:
# most Wi-Fi drivers cannot send from a frozen kernel. Nothing is installed and nothing
# persists across a reboot.

set -euo pipefail

PORT=6666
STATE=/run/netlog.printk

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

case ${1:-} in
listen)
    out=$HOME/netlog-$(date +%Y%m%d-%H%M%S).txt
    echo "This computer's addresses:"
    if [[ $(uname -s) == Darwin ]]; then
        ifconfig | awk '$1 == "inet" && $2 != "127.0.0.1" { print "  " $2 }' || true
    else
        ip -4 -o addr show scope global | awk '{ sub(/\/.*/, "", $4); print "  " $4 }' || true
    fi
    echo "Listening on UDP port $PORT, writing $out. Ctrl-C to stop."
    echo "(macOS may ask whether to allow incoming connections: allow.)"
    nc -u -l "$PORT" | tee "$out"
    ;;
on)
    ip=${2:-}
    [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 on ADDRESS (the address the listener printed)"
    grep -qE '^CONFIG_NETCONSOLE=[ym]' "/boot/config-$(uname -r)" 2>/dev/null ||
        die "this kernel has no netconsole (CONFIG_NETCONSOLE)"
    sudo -v || exit 1
    route=$(ip -o route get "$ip") || die "no route to $ip"
    dev=$(sed -n 's/.* dev \([^ ]*\).*/\1/p' <<<"$route")
    src=$(sed -n 's/.* src \([^ ]*\).*/\1/p' <<<"$route")
    hop=$(sed -n 's/.* via \([^ ]*\).*/\1/p' <<<"$route")
    hop=${hop:-$ip}
    [[ -n $dev && -n $src ]] || die "could not read interface and source address from: $route"
    [[ -d /sys/class/net/$dev/wireless ]] &&
        echo "WARN: $dev is Wi-Fi; lines from a frozen kernel will probably not get out. Use Ethernet if you can."
    ping -c 1 -W 2 "$hop" >/dev/null 2>&1 || true
    mac=$(ip neigh show "$hop" dev "$dev" | sed -n 's/.* lladdr \([0-9a-f:]\{17\}\).*/\1/p')
    [[ -n $mac ]] || die "$hop does not answer on $dev; is the listener on this network?"
    sudo modprobe -r netconsole 2>/dev/null || true
    sudo modprobe netconsole "netconsole=6665@$src/$dev,$PORT@$ip/$mac" || die "netconsole would not load; see dmesg"
    # The console level decides what netconsole sends: keep the old one, then let
    # everything up to informational messages through.
    [[ -e $STATE ]] || sudo cp /proc/sys/kernel/printk "$STATE"
    sudo dmesg -n 7
    echo "Kernel messages now go to $ip:$PORT over $dev. Check with: $0 test"
    ;;
test)
    echo "netlog test at $(date +%T)" | sudo tee /dev/kmsg >/dev/null
    echo "Sent. The listener should show a line with 'netlog test'."
    ;;
off)
    sudo modprobe -r netconsole 2>/dev/null || true
    if [[ -e $STATE ]]; then
        sudo sh -c "cat '$STATE' > /proc/sys/kernel/printk && rm -f '$STATE'"
    fi
    echo "netconsole off."
    ;;
*)
    echo "usage: $0 {listen | on ADDRESS | test | off}" >&2
    exit 2
    ;;
esac
