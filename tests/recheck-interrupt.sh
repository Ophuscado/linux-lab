#!/bin/bash
# recheck, parallel rows: sources 18 (row D) and 20 (row C), branches 22 (C) and 23 (D).
# Expected: A: after SIGINT no process left, no source mounted, log says interrupted; B: same findings through the root re-exec
# Planted: short copy, path on two branches, same-size corrupted copy; quick must miss the last, full must find it.
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home d*.img; mkdir -p home bin
mk() { truncate -s 1500M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1/sub"
        head -c "$2"M /dev/urandom >"m/Library/Folder $1/sub/big_$1.bin"; head -c 1M /dev/urandom >"m/ünï $1.txt"; umount m; fi
    echo "$dev"; }
declare -A D
D[16]=$(mk 16 0); D[17]=$(mk 17 0); D[18]=$(mk 18 300); D[19]=$(mk 19 0); D[20]=$(mk 20 200); D[21]=$(mk 21 0); D[22]=$(mk 22 0); D[23]=$(mk 23 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 16 17 18 19 20 21 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4

S2=$T/mig.sh
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]="20 22"|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 19 21 23"|' \
    -e 's|\[\[ \$EUID != 0 \]\]|[[ -z ${FAKE_ROOT:-} ]]|' -e 's|VERIFY="\$VERIFY")$|VERIFY="$VERIFY" FAKE_ROOT=1)|' "$S" >mig.sh
sed -e "s|sudo python3 -I -c \"\$RECHECK_PY\"|sudo bash -c 'sleep 25; exec python3 -I -c \"\$0\" \"\$@\"' \"\$RECHECK_PY\"|" mig.sh >mig-slow.sh
chmod +x mig.sh mig-slow.sh; grep -c 'sleep 25' mig-slow.sh; grep -c FAKE_ROOT mig.sh
./mig.sh plan D >/dev/null 2>&1; ./mig.sh plan C >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
H=$T/home/migrate/mnt
for n in 18 20; do mkdir -p $H/src-$n; mount -o ro "${D[$n]}p1" $H/src-$n
  rsync -aHAX --ignore-existing $H/src-$n/ home/migrate/pool/; umount $H/src-$n; done
big=$(ls $H/hd-*/Library/"Folder 18"/sub/big_18.bin); truncate -s 100M "$big"
t20=$(ls $H/hd-*/"ünï 20.txt"); printf 'X' | dd of="$t20" bs=1 seek=100 conv=notrunc 2>/dev/null
export MIG_RECHECK_SINCE="$(date -d "-1 hour" "+%F %H:%M")" MIG_RECHECK_UNTIL="$(date -d "+1 hour" "+%F %H:%M")" MIG_RECHECK_DUPS=0
echo "### A: ^C while the byte compare runs (sleep 25 injected); everything must stop"
cat >spawn.py <<'PY'
import os, signal, subprocess
env = dict(os.environ, VERIFY="full")
p = subprocess.Popen(["./mig-slow.sh", "recheck", "18", "20"], start_new_session=True, env=env,
                     stdout=open("ctrlc.out", "w"), stderr=subprocess.STDOUT,
                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
open("pg", "w").write(str(p.pid))
PY
python3 spawn.py
sleep 8; echo "running before ^C:"; pgrep -af 'sleep 25|mig-slow' | cut -c1-90 | head
kill -INT -- -$(cat pg); sleep 5
echo "left after ^C (expect none):"; pgrep -af 'sleep 25|mig-slow|python3 -I' | cut -c1-90
echo "mounted sources (expect none):"; findmnt -rn -o TARGET | grep 'mnt/src-' 
echo "log:"; grep -E 'recheck:|WARN' ctrlc.out | cut -c21-120
echo "### B: whole run through the re-exec: quick finds the short copy, full the byte"
./mig.sh recheck 18 20 2>&1 | grep -E 'recheck:|WARN' | cut -c21-130; echo "exit ${PIPESTATUS[0]}"
VERIFY=full ./mig.sh recheck 18 20 2>&1 | grep -E 'recheck:|WARN' | cut -c21-130; echo "exit ${PIPESTATUS[0]}"
echo "### aside:"; find $H/hd-*/.migrate-aside -type f | sed "s|$H/||"
echo "### leftover tmp dirs in state:"; ls home/migrate/state | grep -E 'recheck\.|walk\.' || echo none
umount "$T/home/migrate/pool"; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
