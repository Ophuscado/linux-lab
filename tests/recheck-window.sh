#!/bin/bash
# recheck on loop devices: a pool copy left short, and a path present on two branches.
# Expected: windowed recheck finds the short copy and the double; which copy of the double survives depends on random placement
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
D[16]=$(mk 16 0); D[17]=$(mk 17 0); D[18]=$(mk 18 300); D[19]=$(mk 19 0); D[20]=$(mk 20 0); D[21]=$(mk 21 0); D[22]=$(mk 22 0); D[23]=$(mk 23 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 16 17 18 19 20 21 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1   # marks the empty ones
./mig.sh add 23 22 2>&1 | tail -n 1
mkdir -p home/migrate/mnt/src-18; mount -o ro "${D[18]}p1" home/migrate/mnt/src-18
rsync -aHAX --filter='-x system.*' --filter='-x osx.*' --filter='-xr security.*' --ignore-existing home/migrate/mnt/src-18/ home/migrate/pool/
umount home/migrate/mnt/src-18
H=$T/home/migrate/mnt
big=$(ls $H/hd-*/Library/"Folder 18"/sub/big_18.bin); echo "big on: $big"
echo "### plant: truncate the big copy; put a second 'ünï 18.txt' on the other branch"
truncate -s 100M "$big"
txt=$(ls $H/hd-*/"ünï 18.txt"); other=$( [[ $txt == */hd-23/* ]] && echo 22 || echo 23 ); echo "second copy" >"$H/hd-$other/ünï 18.txt"; echo "txt on ${txt%/*}, second copy on $other"
echo "### recheck 18, only files created in the last hour"; MIG_RECHECK_SINCE="$(date -d "-1 hour" "+%F %H:%M")" MIG_RECHECK_UNTIL="$(date -d "+1 hour" "+%F %H:%M")" ./mig.sh recheck 18 2>&1 | grep -E 'recheck:' | cut -c21-140
echo "### aside folders:"; find $H/hd-*/.migrate-aside -type f | sed "s|$H/||"
echo "### pool: big gone (short copy aside), txt still there (good copy kept):"; ls "$T/home/migrate/pool/Library/Folder 18/sub/" 2>&1; ls "$T/home/migrate/pool/" | head; cmp "$T/home/migrate/pool/ünï 18.txt" <(mount -o ro "${D[18]}p1" m && cat "m/ünï 18.txt"; umount m) && echo "txt in pool matches the source"
umount "$T/home/migrate/pool"; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
