#!/bin/bash
# A pool branch dies (XFS forced shutdown = EIO on every operation): mode "mid" while the copy runs, mode "start" before it.
# Expected: mode mid or start: the dead branch is dropped and marked bad, both sources verified, 18 of 18 checksums match, good puts it back, a file under the unmounted bay makes good refuse
set -u
MODE=${1:-mid}
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home d*.img hashes.txt; mkdir -p home bin
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1"
        for i in $(seq "$2"); do head -c 60M /dev/urandom >"m/Library/Folder $1/f$i.bin"; done
        (cd m && sha256sum Library/*/*.bin) >>hashes.txt; umount m; fi
    echo "$dev"; }
declare -A D
D[16]=$(mk 16 0); D[17]=$(mk 17 12); D[18]=$(mk 18 6); D[22]=$(mk 22 0); D[23]=$(mk 23 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 16 17 18 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 22 23"|' \
    -e 's|--ignore-existing --info=progress2,stats1 --no-inc-recursive|--ignore-existing --bwlimit=40M --info=progress2,stats1 --no-inc-recursive|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
H=$T/home/migrate/mnt
if [[ $MODE == start ]]; then xfs_io -x -c shutdown "$H/hd-23"; echo "### hd-23 shut down before the worker starts"; fi
timeout 250 ./mig.sh run D >home/wD.out 2>&1 </dev/null &
wp=$!
if [[ $MODE == mid ]]; then sleep 7; xfs_io -x -c shutdown "$H/hd-23"; echo "### hd-23 shut down 7 s into the copy"; fi
wait $wp; echo "worker exit $?"
echo "### log"; grep -hE 'round:|pass|WARN|verified,|formatting|worker finished|ERR|not mounted' home/migrate/D.log | cut -c1-170
grep -h 'ERR' home/wD.out | head -3
echo "df pool: $(df -B1 --output=avail home/migrate/pool 2>&1 | tail -n 2 | tr "\n" " ")  branches xattr: $(getfattr -n user.mergerfs.branches --only-values home/migrate/pool/.mergerfs 2>&1 | cut -c1-300)"
echo "### bad marker: $(ls home/migrate/state | grep '\.bad')   pool branches: $(getfattr -n user.mergerfs.branches --only-values home/migrate/pool/.mergerfs 2>/dev/null | sed 's|[^:]*/hd-||g; s|=RW||g; s|:| |g')"
echo "### status line:"; ./mig.sh status 2>&1 | grep -E '^row D|^bad' 
echo "### content: every file in the pool with its checksum (18 expected)"
(cd home/migrate/pool && sha256sum Library/*/*.bin 2>&1) | sort >pool.sha; sort hashes.txt >src.sha
echo "files in pool: $(grep -c bin pool.sha); matching the sources: $(comm -12 pool.sha src.sha | wc -l); wrong or missing: $(comm -13 src.sha pool.sha | wc -l) / $(comm -23 src.sha pool.sha | wc -l)"
echo "### good 23 after remount"
umount "$H/hd-23" 2>&1 | head -2
mkdir -p "$H/hd-23/Library"; echo stray >"$H/hd-23/Library/stray.txt"
echo "stray on the system disk under the unmounted bay: good must refuse"
./mig.sh good 23 2>&1 | grep -E 'ERR' | cut -c1-230; echo "marker after refusal: $(ls home/migrate/state | grep -c '23.bad')"
rm -rf "$H/hd-23/Library"
./mig.sh good 23 2>&1 | grep -vE 'WARN|lists' | tail -n 2; echo "bad marker left: $(ls home/migrate/state | grep -c '\.bad')"
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
