#!/bin/bash
# A disk moved behind a SAS card: its plan name (an ata- link) is gone, udev names it scsi-SATA_<model>_<serial>.
# Expected: 17 is found by its serial, copied and verified; status lists no missing disk; a failed command
# logged for its device is counted under its name; without the serial link status lists 17 as missing.
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D 2>/dev/null; rm -rf home byid d*.img hashes.txt; mkdir -p home bin byid
mk() { truncate -s 3000M "d$1.img"; dev=$(losetup -f --show "d$1.img")
    parted -s "$dev" mklabel gpt mkpart data ext4 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.ext4 -q -F -L "HD_$1" "${dev}p1"
    if (($2 > 0)); then mkdir -p m; mount "${dev}p1" m; mkdir -p "m/Library/Folder $1"
        for i in $(seq "$2"); do head -c 20M /dev/urandom >"m/Library/Folder $1/f$i.bin"; done
        (cd m && sha256sum Library/*/*.bin) >>hashes.txt; umount m; fi
    echo "$dev"; }
declare -A D
D[16]=$(mk 16 0); D[17]=$(mk 17 6); D[22]=$(mk 22 0); D[23]=$(mk 23 0)
ln -s "${D[17]}" "byid/scsi-SATA_LOOP_DISK_S17"
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  echo "000b,0,${D[16]##*/},${D[16]},S16,LOOP,1.5G,ext4,HD_16,0,0,2,0,16"
  echo "000b,1,sdq,/dev/disk/by-id/ata-LOOP_DISK_S17,S17,LOOP,1.5G,ext4,HD_17,0,0,2,1,17"
  echo "000b,6,${D[22]##*/},${D[22]},S22,LOOP,1.5G,ext4,HD_22,0,0,2,6,22"
  echo "000b,7,${D[23]##*/},${D[23]},S23,LOOP,1.5G,ext4,HD_23,0,0,2,7,23"; } >home/disk-plan.csv
K=$T/home/dmesg; : >"$K"
export MIG_WAIT=5 MIG_MERGERFS=$T/bin/mergerfs MIG_EMPTY_LIMIT=10000000 MIG_MINFREE=64M MIG_PROBE=8 MIG_WATCH=2 PATH=$T/bin:$PATH \
    MIG_PLAN=$T/home/disk-plan.csv MIG_HOME=$T/home/migrate MIG_SRC_FS=ext4 MIG_DMESG=$K MIG_BYID=$T/byid
sed -e 's|\[A\]="24 25 26 27 28 29 30 31"|[A]=""|; s|\[B\]="00 01 02 03 04 05 06 07"|[B]=""|; s|\[C\]="08 09 10 11 12 13 14 15"|[C]=""|; s|\[D\]="16 17 18 19 20 21 22 23"|[D]="16 17 22 23"|' "$S" >mig.sh; chmod +x mig.sh
./mig.sh plan D >/dev/null 2>&1
./mig.sh add 23 22 2>&1 | tail -n 1
echo "### copy of 17, found by its serial"
timeout 250 ./mig.sh run D >home/w.out 2>&1 </dev/null; echo "worker exit $?"
grep -hE 'round:|verified,|ERR' home/migrate/D.log | cut -c21-160
(cd home/migrate/pool && sha256sum Library/*/*.bin 2>&1) | sort >pool.sha; sort hashes.txt >src.sha
echo "files in pool: $(grep -c bin pool.sha); matching the sources: $(comm -12 pool.sha src.sha | wc -l)"
echo "### status with a failed command on 17's device"
echo "[Sat Oct 17 01:00:00 2026] sd 0:0:5:0: [${D[17]##*/}] tag#7 FAILED Result: hostbyte=DID_SOFT_ERROR driverbyte=DRIVER_OK cmd_age=30s" >>"$K"
./mig.sh status 2>&1 | grep -E 'missing from|failed commands'
echo "### the serial link gone"
rm byid/scsi-SATA_LOOP_DISK_S17
./mig.sh status 2>&1 | grep -E 'missing from'
umount "$T/home/migrate/pool" 2>/dev/null; for m in $(findmnt -rn -o TARGET | grep "$T" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
