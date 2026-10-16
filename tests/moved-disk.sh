#!/bin/bash
# Disks 14 and 15 swap bays: status names a port's errors after the disk on it now, and rescan
# never resets a port that holds a disk. A fake sysfs and kernel log, no devices.
# Expected: links name 14 (ata1) for port 0 and "?(domain 000a port 3, no disk now; missing from this box: 15 )" for ata4; rescan 15 writes only host12 host13, rescan 14 only host10
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/migrate-row.sh
F=$T/moved; rm -rf "$F"; mkdir -p "$F/dev" "$F/byid" "$F/home"
SYS=$F/sys; C=$SYS/devices/pci000a:00/000a:00:00.0/000a:01:00.0/000a:02:00.0/000a:03:00.0
mkdir -p "$SYS/class/ata_port" "$SYS/class/scsi_host" "$SYS/block"
# port: ata, host, disk now (14 is in 15's old bay 0, 15 is gone from bay 3, bay 2 is empty)
for spec in "0 1 10 sdq" "1 2 11 sdr" "2 3 12 -" "3 4 13 -"; do
    read -r port ata host blk <<<"$spec"
    mkdir -p "$C/ata$ata/ata_port/ata$ata" "$C/ata$ata/host$host/scsi_host/host$host"
    ln -s "$C/ata$ata/ata_port/ata$ata" "$SYS/class/ata_port/ata$ata"
    ln -s "$C/ata$ata/host$host/scsi_host/host$host" "$SYS/class/scsi_host/host$host"
    if [[ $blk != - ]]; then
        mkdir -p "$C/ata$ata/host$host/target$host:0:0/$host:0:0:0/block/$blk"
        ln -s "$C/ata$ata/host$host/target$host:0:0/$host:0:0:0/block/$blk" "$SYS/block/$blk"
        : >"$F/dev/$blk"
    fi
done
ln -s "$F/dev/sdq" "$F/byid/d14"; ln -s "$F/dev/sdr" "$F/byid/d13"; ln -s "$F/dev/sds" "$F/byid/d15"
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  echo "000a,0,sds,$F/byid/d15,S15,X,18T,xfs,HD_15,0,0,1,0,15"
  echo "000a,1,sdr,$F/byid/d13,S13,X,18T,hfsplus,HD_13,0,0,1,1,13"
  echo "000a,3,sdq,$F/byid/d14,S14,X,18T,hfsplus,HD_14,0,0,1,3,14"; } >"$F/home/disk-plan.csv"
{ for i in 1 2 3; do echo "[Sat Oct 17 10:0$i:00 2026] ata1: SATA link down (SStatus 1 SControl 310)"; done
  for i in 1 2; do echo "[Sat Oct 17 10:0$i:30 2026] ata4: hard resetting link"; done; } >"$F/dmesg"
export MIG_SYS=$SYS MIG_DMESG=$F/dmesg MIG_PLAN=$F/home/disk-plan.csv MIG_HOME=$F/home/migrate MIG_MERGERFS=true \
    MIG_RESCAN_WAIT=0 PATH=$T/bin:$PATH
"$S" status 2>&1 | sed -n '/^links:/,/^mounted:/p' | grep -v '^mounted:'
for nn in 15 14; do
    find "$SYS/devices" -name scan -delete
    "$S" rescan "$nn" >/dev/null 2>&1
    echo "rescan $nn wrote: $(find "$SYS/devices" -name scan | grep -oE 'host[0-9]+/scan' | cut -d/ -f1 | sort -V | tr '\n' ' ')"
done
