#!/bin/bash
# Names the hfsplus driver cannot read: source 17 holds a file and a folder whose names have an emoji,
# both committed to a git repository, and an emoji-named file git does not track, seen through
# hfs-names.py as hfsplus shows them ("??", then not found by that name), beside a readable file whose
# name differs only there and one with a literal '?'.
# Expected: pass 1 ends with code 24, the three names are listed in state/17.unreadable, pass 2 ends
# with code 0; after the verify the two tracked files are written back from git under their real names
# (the untracked one stays behind); 17 is not held (such names are expendable, owner 18 Oct); every
# file but the untracked one in the pool with its content; the sample check passes and the worker
# formats 17 into the pool; it exits 0. 'restore 17' after the format writes nothing again and keeps the record.
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
python3 -c 'import mfusepy' 2>/dev/null || { echo "SKIP: needs mfusepy (pip install mfusepy) and libfuse3"; exit 0; }
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home raw17 d*.img hashes.txt; mkdir -p home bin raw17
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1/dir 😀"
        for i in $(seq "$2"); do head -c 20M /dev/urandom >"m/Library/Folder $1/f$i.bin"; done
        echo unreadable >"m/Library/Folder $1/émoji 😀 book.epub"; echo inside >"m/Library/Folder $1/dir 😀/inner.bin"
        echo look-alike >"m/Library/Folder $1/émoji ab book.epub"; echo literal >"m/Library/Folder $1/what?.txt"
        echo untracked >"m/Library/Folder $1/notes 😀.txt"  # in the repository's folder, but not in git
        git -C "m/Library/Folder $1" init -q && git -C "m/Library/Folder $1" add "émoji 😀 book.epub" "dir 😀/inner.bin" "émoji ab book.epub" &&
            git -C "m/Library/Folder $1" -c user.name=t -c user.email=t@example.org commit -qm t
        (cd m && find Library -type f -exec sha256sum {} +) >>hashes.txt; umount m; fi
    echo "$dev"; }
D16=$(mk 16 0); D17=$(mk 17 6); D22=$(mk 22 0); D23=$(mk 23 0)
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  echo "000b,0,${D16##*/},$D16,S16,LOOP,1.5G,ext4,HD_16,0,0,2,0,16"
  echo "000b,1,${D17##*/},$D17,S17,LOOP,1.5G,ext4,HD_17,0,0,2,1,17"
  echo "000b,6,${D22##*/},$D22,S22,LOOP,1.5G,ext4,HD_22,0,0,2,6,22"
  echo "000b,7,${D23##*/},$D23,S23,LOOP,1.5G,ext4,HD_23,0,0,2,7,23"; } >home/disk-plan.csv
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 MIG_WATCH=2 PATH=$T/bin:$PATH \
    MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DMESG=$T/home/dmesg
: >"$T/home/dmesg"
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 22 23"|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
# 17 as hfsplus would show it, where the worker mounts its source (a mounted source is used as it is)
mount -o ro "${D17}p1" raw17; mkdir -p home/migrate/mnt/src-17
python3 "$REPO/tests/hfs-names.py" raw17 home/migrate/mnt/src-17 2>home/fuse.err &
for _ in 1 2 3 4 5; do findmnt -n home/migrate/mnt/src-17 >/dev/null && break; sleep 1; done
echo "### as hfsplus lists it: $(ls "home/migrate/mnt/src-17/Library/Folder 17" | tr '\n' '|')"
echo "### copy of 17"
timeout 250 ./mig.sh run D >home/w.out 2>&1 </dev/null; echo "worker exit $?"
grep -hE 'rsync pass|cannot read|unreadable names|verified,|ERR' home/migrate/D.log | cut -c21-200
echo "### state/17.restored"; cat home/migrate/state/17.restored
echo "### state/17.unreadable"; cat home/migrate/state/17.unreadable
(cd home/migrate/pool && find Library -type f -exec sha256sum {} + 2>&1) | sort >pool.sha; sort hashes.txt >src.sha
echo "files in pool: $(wc -l <pool.sha); matching the sources: $(comm -12 pool.sha src.sha | wc -l) of $(wc -l <src.sha); not in the pool: $(comm -13 pool.sha src.sha | cut -c67- | tr '\n' '|')"
echo "### status"; ./mig.sh status 2>&1 | grep -E 'held|17' | head -n 4
ls home/migrate/state/ | grep -E '^17\.' | tr '\n' ' '; echo
echo "### the sample check the format waited for:"; cut -c1-120 home/migrate/state/17.sampled
echo "### restore again, after the format: nothing written twice, the first pass kept"; ./mig.sh restore 17 2>&1 | tail -n 1; grep -c '^restored ' home/migrate/state/17.restored
umount home/migrate/mnt/src-17 2>/dev/null; umount raw17 2>/dev/null
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
