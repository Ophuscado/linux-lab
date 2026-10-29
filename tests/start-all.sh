#!/bin/bash
# start with no row: the ended worker's session is replaced, every row gets a worker.
# Expected: start D, then start: the ended D session is replaced, the other rows start, status counts running and ended workers
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
sudo tmux kill-server 2>/dev/null
echo "### start D, wait for it to end"
./mig.sh start D 2>&1 | grep -v WARN
for i in $(seq 60); do sudo tmux capture-pane -p -t mig-D-1 2>/dev/null | grep -q '^worker ended' && break; sleep 2; done
./mig.sh status 2>&1 | grep -E '^row D'
echo "### start (all rows): D replaced, the others started"
./mig.sh start 2>&1 | grep -v WARN
sleep 3; sudo tmux ls -F '#S' | sort | tr '\n' ' '; echo
./mig.sh status 2>&1 | grep -E '^row|links|missing|errors'
sudo tmux kill-server 2>/dev/null
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
