#!/bin/bash
# A pool disk fails a write and dies with it (XFS shut down): the aside cannot walk it.
# Expected: the worker stops, 18 is undone, the stop and status say an aside is pending for 23; an aside by hand on
# the dead disk queues itself (2 pending lines); run refuses
# while 23 is in the pool and still dead ("still does not answer ... 'bad 23'"); after bad 23 run goes on
# without it (17 and 18 verified, pending kept); after a remount, good 23 does the pending aside first
# (two aside lines), status no longer lists it, 23 back in the pool.
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
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
K=$T/home/dmesg; : >"$K"
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 MIG_WATCH=2 PATH=$T/bin:$PATH \
    MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DMESG=$K USER=${USER:-root}
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 22 23"|' \
    -e 's|--ignore-existing --info=progress2,stats1 --no-inc-recursive|--ignore-existing --bwlimit=20M --info=progress2,stats1 --no-inc-recursive|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
H=home/migrate/mnt; d23=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE $H/hd-23)")
( while ! grep -qs '^18 -> pool' home/migrate/state/placement.txt; do sleep 1; done; sleep 4
  xfs_io -x -c shutdown "$H/hd-23"
  echo "[ 1001.000003] I/O error, dev $d23, sector 2983277136 op 0x1:(WRITE) flags 0x104000 phys_seg 65 prio class 2" >>"$K" ) &
echo "### 1: 23 dies with a failed write during 17's copy"
timeout 250 ./mig.sh run D >home/w1.out 2>&1 </dev/null; echo "worker exit $?"; wait
grep -hE 'WARN (18|hd-23)' home/migrate/D.log | sed -E 's/^.*(WARN)/\1/' | cut -c1-170
./mig.sh status 2>&1 | grep -E '^STOPPED|^aside pending' | cut -c1-170
echo "### 1b: aside by hand on the dead disk queues itself"
./mig.sh aside 23 "$(date -d '20 minutes ago' '+%F %T')" "$(date -d '10 minutes ago' '+%F %T')" 2>&1 | grep -E 'aside:|ERR' | sed -E 's/^[0-9-]+ [0-9:]+ //' | cut -c1-150
echo "pending lines: $(wc -l < home/migrate/state/aside-pending)"
echo "### 2: run while 23 is in the pool and dead"
timeout 60 ./mig.sh run D 2>&1 </dev/null | grep ERR | cut -c1-170
echo "### 3: bad 23, run"
./mig.sh bad 23 2>&1 | grep -E 'pool now' 
timeout 250 ./mig.sh run D >home/w3.out 2>&1 </dev/null; echo "worker exit $?"
grep -hE 'verified,|lifted' home/migrate/D.log | tail -n 3 | sed -E 's/^[0-9-]+ [0-9:]+ //' | cut -c1-120
echo "pending: $(cat home/migrate/state/aside-pending 2>/dev/null | tr '\t' ' ')"
echo "### 4: 23 remounted, good 23"
./mig.sh good 23 2>&1 | grep -E 'aside:|ERR|pool:' | sed -E 's/^[0-9-]+ [0-9:]+ //' | cut -c1-150
echo "pending left: $(ls home/migrate/state | grep -c aside-pending); status: $(./mig.sh status 2>&1 | grep -c '^aside pending') lines"
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
