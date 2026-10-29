#!/bin/bash
# policy switches where the pool puts new files, on the live mount and for later mounts and
# workers (which re-apply the policy when they find the pool mounted).
# Expected: live mfs after "policy mfs"; status says new files by mfs; still mfs after "pool" on the mounted pool and after a fresh mount; pfrd after "policy pfrd"; a new file lands on the emptier branch under mfs
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home d*.img; mkdir -p home
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null 2>&1; partprobe "$dev" 2>/dev/null; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"; echo "$dev"; }
declare -A D; D[22]=$(mk 22); D[23]=$(mk 23)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,3G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="22 23"|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh erase 22 23 >/dev/null 2>&1; ./mig.sh add 23 22 2>&1 | tail -n 1
H=$T/home/migrate/mnt; P=$T/home/migrate/pool
head -c 1500M /dev/zero >"$H/hd-23/filler"   # 23 is now the fuller branch
./mig.sh policy mfs 2>&1 | grep -E '^(kept|live)'
./mig.sh pool 2>&1 | tail -n 1; echo "after pool on the mounted pool: $(getfattr -n user.mergerfs.category.create --only-values "$P/.mergerfs")"
umount "$P"; ./mig.sh pool >/dev/null 2>&1; echo "after a fresh mount: $(getfattr -n user.mergerfs.category.create --only-values "$P/.mergerfs")"
for i in 1 2 3; do echo x >"$P/new$i"; done; echo "new files on: $(cd "$H" && ls -d hd-*/new* | cut -d/ -f1 | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
./mig.sh status 2>&1 | grep -oE 'new files by [a-z]+'
./mig.sh policy pfrd 2>&1 | grep -E '^live'
umount "$P" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
