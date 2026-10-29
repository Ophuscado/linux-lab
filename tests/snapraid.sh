#!/bin/bash
# snapraid-setup.sh on loop devices: parity 24 00 08 16, data 25 01 09 17 (content disks).
# Expected: snapraid sync and scrub pass, a flipped byte is found by check and repaired by fix
set -u
. "$(dirname "$0")/lib.sh"
S=$REPO/storage/snapraid-setup.sh
cd "$T" || exit 1
for m in $(findmnt -rn -o TARGET | grep "$T/sr" | sort -r); do umount "$m" 2>/dev/null; done
losetup -D; rm -rf sr d*.img; mkdir -p sr/etc sr/mnt sr/content sr/pool sr/out bin
printf '#!/bin/sh\nexit 0\n' >bin/dnf; chmod +x bin/dnf
declare -A D
for n in 24 00 08 16 25 01 09 17; do
    truncate -s 3000M "d$n.img"; dev=$(losetup -f --show "d$n.img")
    parted -s "$dev" mklabel gpt mkpart data xfs 1MiB 100% >/dev/null; partprobe "$dev"; sleep 1
    mkfs.xfs -q -f -L "HD_$n" "${dev}p1"; D[$n]=$dev
done
{ echo "domain,port,dev,byid,serial,model,size,fstype,label,used,avail,row,slot,name"
  for n in 24 00 08 16 25 01 09 17; do echo "000b,0,${D[$n]##*/},${D[$n]},S$n,LOOP,3G,xfs,HD_$n,0,0,2,0,$n"; done; } >sr/plan.csv
export PATH=$T/bin:$PATH SR_PLAN=$T/sr/plan.csv SR_ROOT=$T/sr/mnt SR_POOL=$T/sr/pool SR_ETC=$T/sr/etc SR_CONTENT=$T/sr/content SR_MIG=$T/sr/nomig SR_OUT=$T/sr/out
echo "### conf"; "$S" conf | head -n 12
echo "### install"; "$S" install; grep -c LABEL sr/etc/fstab; grep -c 'fuse.mergerfs' sr/etc/fstab
echo "### install again replaces the block"; "$S" install >/dev/null; grep -c 'begin' sr/etc/fstab
echo "### mount by hand as fstab would (data, parity), then the pool"
for n in 25 01 09 17; do mount "${D[$n]}p1" "sr/mnt/data/$n"; done
for n in 24 00 08 16; do mount "${D[$n]}p1" "sr/mnt/parity/$n"; done
mergerfs -o allow_other,category.create=pfrd,moveonenospc=true,minfreespace=64M,cache.files=off,dropcacheonclose=true,fsname=pool "$T/sr/mnt/data/25:$T/sr/mnt/data/01:$T/sr/mnt/data/09:$T/sr/mnt/data/17" sr/pool
mkdir -p "sr/pool/Library/Folder A/sub"; for i in 1 2 3 4 5 6; do head -c 50M /dev/urandom >"sr/pool/Library/Folder A/sub/f$i.bin"; done; head -c 1M /dev/urandom >"sr/pool/ünï.txt"
echo "files per disk: $(for n in 25 01 09 17; do printf '%s=%s ' $n "$(find sr/mnt/data/$n -type f | wc -l)"; done)"
echo "### first (sync + scrub)"; "$S" first 2>&1 | grep -E 'Everything OK|Nothing|error|Error|WARN|content|parity|%' | head -n 12
echo "### damage one file, snapraid check must see it, fix must repair it"
f=$(find sr/mnt/data -name 'f*.bin' | head -n 1)
printf 'XXXX' | dd of="$f" bs=1 seek=1000 conv=notrunc 2>/dev/null
snapraid -c sr/etc/snapraid.conf check 2>&1 | grep -E 'error|OK' | tail -n 2
snapraid -c sr/etc/snapraid.conf fix 2>&1 | grep -E 'recovered|OK|error' | tail -n 2
snapraid -c sr/etc/snapraid.conf check 2>&1 | grep -E 'error|OK' | tail -n 1
echo "### mount refuses while migration runs (fake pool mount)"; mkdir -p sr/nomig/pool; mount -t tmpfs none sr/nomig/pool; "$S" mount 2>&1 | tail -n 1; umount sr/nomig/pool
umount sr/pool; for m in $(findmnt -rn -o TARGET | grep "$T/sr" | sort -r); do umount "$m" 2>/dev/null; done; losetup -D
echo "### timers (units written to a test dir; systemctl may be absent here)"
SR_UNITS=$T/sr/units "$S" timers on 2>&1 | grep -vE 'systemctl|System has not been booted|Failed to connect' | tail -n 2; ls sr/units; grep -h ExecStart sr/units/*.service
