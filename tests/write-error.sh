#!/bin/bash
# A pool disk fails a write (kernel log "I/O error, dev X, ... (WRITE)") while row D copies.
# Expected:
#  1. a WRITE error on a disk outside the pool and a READ error on hd-23 change nothing: 18 is verified
#  2. a WRITE error on hd-23's disk during 17's copy: within MIG_WATCH the worker logs it, moves the files
#     written to hd-23 since 30 min before aside on hd-23, makes 18 a source again, stops (exit 1),
#     17 and 18 not marked, both still ext4; status says STOPPED
#  2b. aside 23 by hand: 0 files moved
#  3. run again (trusts the disks): the stop is lifted, the old lines are not handled again, 18 and 17 are
#     copied and verified, 18 of 18 checksums match in the pool, the moved files stay on hd-23 under .migrate-aside
#  4. bad 23 after both were formatted: the warning that their files may exist only on 23
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
    MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DMESG=$K
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 22 23"|' \
    -e 's|--ignore-existing --info=progress2,stats1 --no-inc-recursive|--ignore-existing --bwlimit=20M --info=progress2,stats1 --no-inc-recursive|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
d23=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE home/migrate/mnt/hd-23)")
echo "hd-23 is on $d23"
echo "[ 1000.000001] I/O error, dev sdz, sector 8 op 0x1:(WRITE) flags 0x104000 phys_seg 65 prio class 2" >>"$K"
echo "[ 1000.000002] I/O error, dev $d23, sector 8 op 0x0:(READ) flags 0x4000 phys_seg 168 prio class 2" >>"$K"
echo "### 1 and 2"
( while ! grep -qs '^18 -> pool' home/migrate/state/placement.txt; do sleep 1; done; sleep 4
  echo "[ 1001.000003] I/O error, dev $d23, sector 2983277136 op 0x1:(WRITE) flags 0x104000 phys_seg 65 prio class 2" >>"$K"
  echo "### WRITE error on $d23 logged at $(date +%T)" ) &
timeout 250 ./mig.sh run D >home/w1.out 2>&1 </dev/null; echo "worker exit $?"; wait
grep -hE 'round:|verified,|WARN|formatting|stop' home/migrate/D.log | cut -c21-230
grep -h 'ERR' home/w1.out | cut -c1-230
echo "17.copied: $(ls home/migrate/state/17.copied 2>/dev/null || echo none); 18.copied: $(ls home/migrate/state/18.copied 2>/dev/null || echo none); 17 and 18 still: $(blkid -p -s TYPE -o value "${D[17]}p1") $(blkid -p -s TYPE -o value "${D[18]}p1")"
echo "aside on hd-23: $(find home/migrate/mnt/hd-23/.migrate-aside -type f 2>/dev/null | wc -l) files; seen lines: $(wc -l <home/migrate/state/write-errors.seen)"
echo "### status"; ./mig.sh status 2>&1 | grep -E '^row D|STOPPED' | cut -c1-200
echo "### 2b: aside by hand (nothing left to move)"; ./mig.sh aside 23 "$(date -d '10 minutes ago' '+%F %T')" 2>&1 | grep -E 'aside:|ERR' | cut -c21-200
echo "### 3: run again"
timeout 250 ./mig.sh run D >home/w2.out 2>&1 </dev/null; echo "worker exit $?"
grep -hE 'lifted|round:|verified,|WARN|worker finished' home/migrate/D.log | tail -n 7 | cut -c21-200
(cd home/migrate/pool && sha256sum Library/*/*.bin 2>&1) | sort >pool.sha; sort hashes.txt >src.sha
echo "files in pool: $(grep -c bin pool.sha); matching the sources: $(comm -12 pool.sha src.sha | wc -l); still aside on hd-23: $(find home/migrate/mnt/hd-23/.migrate-aside -type f | wc -l)"
echo "### 4: bad 23 after the formats"
./mig.sh bad 23 2>&1 | grep -E 'WARN' | cut -c21-200
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
