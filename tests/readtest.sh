#!/bin/bash
# readtest reads every present disk of a row in tmux session test-ROW; check shows rates, a lost
# disk, and only the errors logged after the start; stop ends it.
# Expected: start reads 2 disks (18 missing); check: both disks with GB read > 0, only the link error logged after the start (ata7, not ata6); a disk the system lost shows GONE; stop: stopped
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
tmux kill-server 2>/dev/null; losetup -D 2>/dev/null; rm -rf home rt*.img fsys; mkdir -p home
D16=$(truncate -s 4G rt16.img && losetup -f --show rt16.img); D17=$(truncate -s 4G rt17.img && losetup -f --show rt17.img)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  echo "000b,0,${D16##*/},$D16,S16,LOOP,4G,,,0,0,2,0,16"; echo "000b,1,${D17##*/},$D17,S17,LOOP,4G,,,0,0,2,1,17"
  echo "000b,2,sdzz,/dev/disk/by-id/gone-18,S18,LOOP,4G,,,0,0,2,2,18"; } >home/disk-plan.csv
echo "[Fri Oct 16 10:00:00 2026] ata6: SATA link down (SStatus 1 SControl 310)" >home/dmesg
export MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_DMESG=$T/home/dmesg MIG_MERGERFS=true PATH=$T/bin:$PATH
sed -e 's|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 18"|' "$S" >rt.sh; chmod +x rt.sh
./rt.sh readtest D start 2>&1 | grep -v WARN
sleep 2
echo "[Fri Oct 16 10:05:01 2026] ata7: SATA link down (SStatus 1 SControl 310)" >>home/dmesg
./rt.sh readtest D 2>&1 | grep -v WARN
mkdir -p fsys/block; ln -sfn "/sys/block/${D16##*/}" "fsys/block/${D16##*/}"   # the system lost 17
MIG_SYS=$T/fsys ./rt.sh readtest D 2>&1 | grep -E '^    1[67]'
./rt.sh readtest D stop
tmux kill-server 2>/dev/null; losetup -D
