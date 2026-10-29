#!/bin/bash
# extra copies a disk outside the plan (disk 33, given as PART here) into the pool in tmux session
# mig-33, skips what is there on a second run, and status shows it.
# Expected: 12 of 12 files match, volume files copied: 0; second run sends under 1 kB, code 0; status: disk 33 (USB): copy ended, then rsync finished with code 0;
# --into: 12 of 12 files match in the other pool, owned by nobody (SUDO_USER); stop: disk 33 stopped, src-33 unmounted
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
tmux kill-server 2>/dev/null
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home d*.img hashes.txt; mkdir -p home bin
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Projects/repo $1/.git" m/.Spotlight-V100
        for i in $(seq "$2"); do head -c 20M /dev/urandom >"m/Projects/repo $1/.git/f$i.bin"; done
        echo junk >m/.Spotlight-V100/store
        (cd m && sha256sum Projects/*/.git/*.bin) >>hashes.txt; umount m; fi
    echo "$dev"; }
declare -A D
D[22]=$(mk 22 0); D[23]=$(mk 23 0); U=$(mk 33 12)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 22 23; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,1.5G,ext4,HD_$n,0,0,2,0,$n"; done; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 PATH=$T/bin:$PATH MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="22 23"|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh erase 22 23 >/dev/null 2>&1; ./mig.sh add 23 22 2>&1 | tail -n 1
run() { ./mig.sh extra "${U}p1" 2>&1 | grep -v WARN
    for _ in $(seq 60); do tmux capture-pane -p -t mig-33 2>/dev/null | grep -q 'worker ended' && break; sleep 1; done; }
run
P=$T/home/migrate/pool
echo "$( (cd "$P" && sha256sum -c "$T/hashes.txt" 2>/dev/null) | grep -c ': OK$') of $(wc -l <hashes.txt) files match; volume files copied: $(ls -A "$P" | grep -c Spotlight)"
run
grep -E '^sent |rsync finished' home/migrate/33.log | tail -n 2
./mig.sh status 2>&1 | grep -A1 '^disk 33'
mkdir -p final && mount -t tmpfs -o size=400M tmpfs final
SUDO_USER=nobody ./mig.sh extra --into "$T/final" "${U}p1" 2>&1 | grep -v WARN
for _ in $(seq 60); do tmux capture-pane -p -t mig-33 2>/dev/null | grep -q 'worker ended' && break; sleep 1; done
echo "--into: $( (cd final && sha256sum -c "$T/hashes.txt" 2>/dev/null) | grep -c ': OK$') of $(wc -l <hashes.txt) files match in the other pool"
echo "--into owners: $(find final -type f -printf '%u\n' | sort -u | tr '\n' ' ')"
./mig.sh extra stop 2>&1 | grep -v WARN | head -n 1
findmnt -n "$T/home/migrate/mnt/src-33" >/dev/null && echo "src-33 still mounted" || echo "src-33 unmounted"
tmux kill-server 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
