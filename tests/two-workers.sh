#!/bin/bash
# migrate-row.sh global pool on loop devices: rows C (08 09 10 15) and D (16 17 18 23), one worker each.
# Expected: six sources verified, each data set once in the pool with its hard links, parity disks formatted last, finish unmounts everything, a rerun is a no-op
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T"); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home r3 d*.img; mkdir -p home bin r3
mk() { # name, megabytes of data
    truncate -s 1500M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then
        mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1/sub"
        head -c "$2"M /dev/urandom >"m/Library/Folder $1/sub/big_$1.bin"; head -c 1M /dev/urandom >"m/ünï $1.txt"
        ln "m/ünï $1.txt" "m/Library/hard_$1.txt"; chown 501:20 "m/Library/Folder $1"; umount m
    fi
    echo "$dev"
}
declare -A D
D[08]=$(mk 08 200); D[09]=$(mk 09 1100); D[10]=$(mk 10 300); D[15]=$(mk 15 150)
D[16]=$(mk 16 200); D[17]=$(mk 17 800); D[18]=$(mk 18 500); D[23]=$(mk 23 20)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 08 09 10 15 16 17 18 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
printf '#!/bin/sh\nexit 0\n' >bin/dnf; chmod +x bin/dnf
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]="08 09 10 15"|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18 23"|' "$S" >mig.sh; chmod +x mig.sh
echo "### erase 15 23, defer 10"; ./mig.sh erase 15 23 2>&1 | sed "s|/dev/||g" | grep -v WARN; ./mig.sh defer 10 | grep -v WARN
mkdir -p home/migrate/state/claim-23
echo "### add 23 now (marked, with a stale claim), refuse 17 (data) and 16 (parity)"; ./mig.sh add 23 2>&1 | grep -v WARN | tail -n 2; ./mig.sh add 17 2>&1 | grep ERR; ./mig.sh add 16 2>&1 | grep ERR
echo "### plan C"; ./mig.sh plan C 2>&1 | sed "s|/dev/||g" | grep -v WARN
mkdir -p home/migrate/state/claim-09; echo 5000000000 >home/migrate/state/claim-09/need; echo "### stale claim on 09 (dead pid, 5 GB reserved) planted"
echo "### two workers, rows C and D, at once"
timeout 200 ./mig.sh run C >r3/wC.out 2>&1 </dev/null &
sleep 2
timeout 200 ./mig.sh run D >r3/wD.out 2>&1 </dev/null &
wait
echo "### rounds (log)"; grep -hE 'round:|verified,|formatting|worker finished|ERR|reservation' home/migrate/C.log home/migrate/D.log | cut -c1-120
echo "### placement"; cat home/migrate/state/placement.txt
echo "### content: every data set present exactly once"
H=$T/home/migrate/mnt
for n in 08 09 10 16 17 18; do echo "files of $n in pool: $(find $H/hd-*/ -name "*_$n.*" -type f | wc -l) (3 expected) hardlinks: $(stat -c %h $H/hd-*/Library/hard_$n.txt 2>/dev/null | tr "\n" " ")"; done
echo "pool: $(ls "$T/home/migrate/pool/Library" | wc -l) entries in Library; $(find "$T/home/migrate/pool" -type f | wc -l) files; branches: $(getfattr -n user.mergerfs.branches --only-values $T/home/migrate/pool/.mergerfs | sed 's|=RW||g; s|[^:]*/hd-||g')"
for n in 08 16; do echo "parity $n: $(blkid -p -s TYPE -o value "${D[$n]}p1")"; done
echo "### status"; ./mig.sh status 2>&1 | grep -v WARN | head -8
echo "### finish"; ./mig.sh finish 2>&1 | grep -v WARN: | tail -n 3; findmnt -rn -o TARGET | grep -c "home/migrate" || true
echo "### rerun no-op"; ./mig.sh run C 2>&1 | tail -n 1 | cut -c1-100
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T"); do umount "$m" 2>/dev/null; done
losetup -D
