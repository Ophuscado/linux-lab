#!/bin/bash
# migrate-row.sh eager mode and the HFS+-compressed guard on loop devices: row C (08 09 10 15), one worker,
# the eager loop beside it. ext4 stands in for HFS+ and the attribute user.decmpfs for osx.com.apple.decmpfs.
# Expected: 15 erased and the first branch; 10 verified but held (its compressed file listed with its real
# size 123456, the plain empty file not), still ext4, refused by add; 09 formatted and added by the eager loop
# before the row ends; parity 08 formatted, not a branch; status shows eager and held; after 'rescued 10' a
# round skips 10 while its verify is younger than the margin and while a stop stands, then adds it
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
tmux kill-server 2>/dev/null
for m in $(findmnt -rn -o TARGET | grep "$T"); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home r4 d*.img; mkdir -p home bin r4
mk() { # name, megabytes of data
    truncate -s 4G "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then
        mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Books $1"
        head -c "$2"M /dev/urandom >"m/Books $1/big_$1.bin"; : >"m/Books $1/empty_$1.txt"
        if [[ $1 == 10 ]]; then
            : >"m/Books $1/compressed.epub"
            setfattr -n user.decmpfs -v 0x66706d630400000040e2010000000000 "m/Books $1/compressed.epub"
        fi
        umount m
    fi
    echo "$dev"
}
declare -A D
D[08]=$(mk 08 100); D[09]=$(mk 09 300); D[10]=$(mk 10 200); D[15]=$(mk 15 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 08 09 10 15; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,4G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv \
    MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DECMPFS=user.decmpfs MIG_WRITE_MARGIN=0 MIG_EAGER_EVERY=1 MIG_DMESG=$T/r4/dmesg
: >r4/dmesg
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]="08 09 10 15"|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]=""|' "$S" >mig.sh; chmod +x mig.sh
B=$T/home/migrate/pool/.mergerfs
branches() { getfattr -n user.mergerfs.branches --only-values "$B" 2>/dev/null | sed 's|=RW||g; s|[^:]*/hd-||g; s|:| |g'; }
echo "### erase 15; eager on"; ./mig.sh erase 15 2>&1 | grep -v WARN | tail -n 1; ./mig.sh eager on 2>&1 | grep -v WARN
echo "eager session: $(tmux has-session -t mig-eager 2>/dev/null && echo running || echo none)"
echo "### one worker, row C, the eager loop beside it"
timeout 300 ./mig.sh run C >r4/w.out 2>&1 </dev/null
sleep 3
echo "### log, in order"
cat home/migrate/C.log home/migrate/heal.log | grep -E '^[0-9]{4}-' | sort -s -k1,2 | grep -E 'verified,|held|compressed|eager:|formatted$|formatting parity|worker finished' | cut -c21-170
echo "### state"
echo "10.compressed: $(tr '\t' ' ' <home/migrate/state/10.compressed)"
echo "10: $(blkid -p -s TYPE -o value "${D[10]}p1"), held: $([[ -f home/migrate/state/10.held ]] && echo yes || echo no), copied: $([[ -f home/migrate/state/10.copied ]] && echo yes || echo no)"
echo "09: $(blkid -p -s TYPE -o value "${D[09]}p1"); 08 (parity): $(blkid -p -s TYPE -o value "${D[08]}p1"); branches: $(branches)"
echo "### status"; ./mig.sh status 2>&1 | grep -E '^(eager|held):'
echo "### add 10 refused"; ./mig.sh add 10 2>&1 | grep -E 'ERR|held' | cut -c1-120
echo "### eager off; rescued 10; rounds"
./mig.sh eager off; echo "eager session: $(tmux has-session -t mig-eager 2>/dev/null && echo running || echo none)"
./mig.sh rescued 10
touch home/migrate/state/eager home/migrate/state/10.copied
MIG_WRITE_MARGIN=1 MIG_EAGER_ROUNDS=1 ./mig.sh eager-loop
echo "verify just now, margin 1 min: 10 $(blkid -p -s TYPE -o value "${D[10]}p1"), branches: $(branches)"
touch -d '5 minutes ago' home/migrate/state/10.copied; echo "a test stop" >home/migrate/state/stop
MIG_WRITE_MARGIN=1 MIG_EAGER_ROUNDS=1 ./mig.sh eager-loop
echo "verify 5 min ago, a stop stands: 10 $(blkid -p -s TYPE -o value "${D[10]}p1"), branches: $(branches)"
rm -f home/migrate/state/stop
MIG_WRITE_MARGIN=1 MIG_EAGER_ROUNDS=1 ./mig.sh eager-loop
echo "verify 5 min ago, no stop: 10 $(blkid -p -s TYPE -o value "${D[10]}p1"), branches: $(branches)"
rm -f home/migrate/state/eager
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T"); do umount "$m" 2>/dev/null; done
losetup -D
