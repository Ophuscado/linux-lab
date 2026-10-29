#!/bin/bash
# A worker takes up a new version of the script between two sources, and restart keeps a row's two workers.
# Expected: 18 is copied first (the smaller), the script changes while it copies; after 18 is verified the
# worker logs "a new version", starts again "on a new version" and copies 17; 'start D 2' gives the row a
# second worker, 'restart D' ends both ("2 worker(s) ended") and starts two again (mig-D-1, mig-D-2); 17 and
# 18 verified in the end, 18 of 18 checksums; status names each disk's role.
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
sudo tmux kill-server 2>/dev/null
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home d*.img hashes.txt; mkdir -p home bin
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1"
        for i in $(seq "$2"); do head -c 30M /dev/urandom >"m/Library/Folder $1/f$i.bin"; done
        (cd m && sha256sum Library/*/*.bin) >>hashes.txt; umount m; fi
    echo "$dev"; }
declare -A D
D[16]=$(mk 16 0); D[17]=$(mk 17 12); D[18]=$(mk 18 6); D[22]=$(mk 22 0); D[23]=$(mk 23 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 16 17 18 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 MIG_WATCH=2 PATH=$T/bin:$PATH \
    MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DMESG=$T/home/dmesg USER=${USER:-root}
: >"$MIG_DMESG"
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 22 23"|' \
    -e 's|--ignore-existing --info=progress2,stats1 --no-inc-recursive|--ignore-existing --bwlimit=4M --info=progress2,stats1 --no-inc-recursive|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
./mig.sh start D 2>&1 | grep -E 'started|ERR'
for i in $(seq 60); do grep -q '18>pool: copying' home/migrate/D.log 2>/dev/null && break; sleep 1; done
echo '# a new version (test)' >>mig.sh
echo "### the script changed while 18 copies"
for i in $(seq 300); do grep -q '17>pool: copying' home/migrate/D.log 2>/dev/null && break; sleep 1; done
grep -hE 'a new version|worker start' home/migrate/D.log | cut -c21-120
echo "### status while 17 copies"; ./mig.sh status 2>&1 | grep '^row D' | cut -c1-200
./mig.sh start D 2 2>&1 | grep -E 'started|running|replaced'
sleep 5
echo "### restart D"; ./mig.sh restart D 2>&1 | grep -vE '^WARN' | cut -c1-110
grep -h 'ended for a restart' home/migrate/heal.log | cut -c21-120
echo "sessions: $(sudo tmux ls -F '#S' 2>/dev/null | grep '^mig-D-' | tr '\n' ' ')"
for i in $(seq 400); do grep -q '17>pool: verified' home/migrate/D.log 2>/dev/null && break; sleep 1; done
grep -hE 'verified,|ERR' home/migrate/D.log | cut -c21-140
(cd home/migrate/pool && sha256sum Library/*/*.bin 2>&1) | sort >pool.sha; sort hashes.txt >src.sha
echo "files in pool: $(grep -c bin pool.sha); matching the sources: $(comm -12 pool.sha src.sha | wc -l)"
sudo tmux kill-server 2>/dev/null
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
