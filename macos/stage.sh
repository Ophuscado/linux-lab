#!/usr/bin/env bash
# stage.sh: put what a macOS run of collect.sh needs on the exFAT disk both systems read, so macOS
# downloads only llama.cpp's source and two Python packages.
#
#   macos/stage.sh [LABEL]     mount the exFAT disk LABEL (default BACKUP) if needed, then copy into
#                              <disk>/linux-lab-macos/: this repository's files (git archive of HEAD)
#                              and the models of macos/models.txt from ~/Projects/_llm, in its
#                              order (by priority), as many as fit with 20 GB left free; STAGE_ONLY="llama2
#                              gemma qwen" copies only those, STAGE_MTP_ONLY=1 only their MTP files
#   macos/stage.sh meta [LABEL]
#                              only write, beside the models folder, models-meta.txt (the GGUF metadata of
#                              each Linux file: size, name, repository, quantizer, parts) and, when absent,
#                              models.env (every NAME= empty, the metadata in comments) for the paths of
#                              models downloaded on macOS instead; the full stage writes them too. While
#                              another stage or backup holds the disk on, writes there without touching it
#   macos/stage.sh results     list the result archives macOS left on the disk, and unpack the newest
#                              into var/macos/
#
# On macOS: bash /Volumes/BACKUP/linux-lab-macos/linux-lab/macos/collect.sh
set -euo pipefail
die() { echo "ERR: $*" >&2; exit 1; }
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
LLM=${LLM:-$HOME/Projects/_llm}
KEEP=$((20 * 1024 * 1024 * 1024))
cmd=stage; [[ ${1:-} == results || ${1:-} == meta ]] && { cmd=$1; shift; }
label=${1:-BACKUP}

exfat() { lsblk -rno PATH,LABEL,FSTYPE | awk -v l="$label" '$3 == "exfat" && $2 == l {print $1; exit}'; }
# The exFAT partition sits on the backup disk, which backup-disk.sh keeps powered off: power it on, keep any
# backup from running (and powering it off) meanwhile, and power it off again at the end.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/backup-home.lock"
held=""
if ! flock -n 9; then
    # Small files only: next to a running stage or backup, on the disk as it is mounted now.
    [[ $cmd == meta ]] || die "a backup or another stage is running; try again when it ends"
    held=1
fi
woke=""
dev=$(exfat)
if [[ -z $dev && -z $held && -f /etc/backup-disk.conf ]]; then
    "$LAB/storage/backup-disk.sh" on >/dev/null && woke=1
    for ((i = 0; i < 30; i++)); do dev=$(exfat); [[ -n $dev ]] && break; sleep 1; done
fi
[[ -n $woke ]] && trap '"$LAB/storage/backup-disk.sh" off' EXIT
[[ -n $dev ]] || die "no exFAT partition labeled $label is plugged in"
m=$(findmnt -n -o TARGET -S "$dev" || true)
if [[ -z $m ]]; then
    [[ -z $held ]] || die "$dev is not mounted and another stage or backup holds the disk; try again when it ends"
    udisksctl mount -b "$dev" >/dev/null; m=$(findmnt -n -o TARGET -S "$dev")
fi
T=$m/linux-lab-macos

# models-meta.txt always; models.env only when absent (it holds the paths filled in on macOS).
write_meta() {
    local name file mtp f k env=$T/models.env new=""
    mkdir -p "$T"
    [[ -f $env ]] || { new=1; {
        echo "# collect.sh reads this on macOS: NAME=/absolute/path of a model downloaded there, NAME_MTP= for its MTP"
        echo "# file. Empty: the copy stage.sh put in models/ (see models-meta.txt for what each one is). For a model"
        echo "# split in parts, give the first part (...-00001-of-0000N.gguf); llama.cpp loads the others beside it."
        echo "# Read as data, not run: one NAME=path per line, quotes optional, ~/ allowed."
    } >"$env.part"; }
    { echo "# GGUF metadata of the Linux model files (macos/gguf-meta.py), $(date -I)"
      while IFS='|' read -r name file mtp; do
        for f in "$file" ${mtp:+"$mtp"}; do
            k=$(tr '[:lower:]' '[:upper:]' <<<"$name"); [[ $f == "$mtp" ]] && k+=_MTP
            echo; echo "[$k] $f"
            if [[ -f $LLM/$f ]]; then python3 -I "$LAB/macos/gguf-meta.py" "$LLM/$f" | tail -n +2; else echo "  not on this Linux machine"; fi
        done
      done < <(grep -v -E '^\s*(#|$)' "$LAB/macos/models.txt"); } >"$T/models-meta.txt.part"
    mv "$T/models-meta.txt.part" "$T/models-meta.txt"
    if [[ -n $new ]]; then
        while IFS='|' read -r name file mtp; do
            for f in "$file" ${mtp:+"$mtp"}; do
                k=$(tr '[:lower:]' '[:upper:]' <<<"$name"); [[ $f == "$mtp" ]] && k+=_MTP
                { echo
                  awk -v k="[$k] " 'index($0, k) == 1 {on = 1; next} /^\[/ {on = 0}
                      on && /^  (size|general\.(name|size_label|repo_url|source\.url|quantized_by|file_type)|split\.count):/ {sub(/^  /, "# "); print}' "$T/models-meta.txt"
                  echo "# on Linux: $f"
                  echo "$k="; } >>"$env.part"
            done
        done < <(grep -v -E '^\s*(#|$)' "$LAB/macos/models.txt")
        mv "$env.part" "$env"
    fi
    echo "$T/models-meta.txt${new:+, $env (new)}"
}
if [[ $cmd == meta ]]; then write_meta; exit 0; fi

if [[ $cmd == results ]]; then
    ls -la "$T/results" 2>/dev/null || die "no results on $m yet"
    a=$(ls -t "$T"/results/*.tar.gz | head -n 1)
    mkdir -p "$LAB/var/macos" && tar -xzf "$a" -C "$LAB/var/macos" && echo "unpacked $a into $LAB/var/macos"
    exit 0
fi

mkdir -p "$T/linux-lab" "$T/models" "$T/results"
git -C "$LAB" archive HEAD | tar -x -C "$T/linux-lab" --no-same-owner --no-same-permissions
echo "linux-lab $(git -C "$LAB" log -1 --format='%h %s') -> $T/linux-lab"
write_meta
while IFS='|' read -r name file mtp; do
    [[ -z ${STAGE_ONLY:-} || " $STAGE_ONLY " == *" $name "* ]] || continue
    for f in "$file" ${mtp:+"$mtp"}; do
        # STAGE_MTP_ONLY=1: only the MTP files, which no public repository names (their headers carry no repo_url).
        [[ ${STAGE_MTP_ONLY:-0} != 1 || $f == "$mtp" ]] || continue
        src=$LLM/$f dst=$T/models/$f
        [[ -f $src ]] || { echo "$name: $src missing, skipped"; continue; }
        size=$(stat -c %s "$src")
        if [[ -f $dst && $(stat -c %s "$dst") == "$size" ]]; then echo "$name: $f there already"; continue; fi
        free=$(df -B1 --output=avail "$m" | tail -n 1)
        ((free - size > KEEP)) || { echo "$name: $f ($((size >> 30)) GiB) does not fit with 20 GB left; stopping here"; break 2; }
        mkdir -p "$(dirname "$dst")"
        echo "$name: copying $f ($((size >> 30)) GiB)"
        # Direct I/O in 64 MiB writes: through the page cache, under the dirty-page cap usb-cap sets for USB disks,
        # cp at idle priority wrote this disk at 1 MiB/s (link at 5 Gb/s).
        t0=$(date +%s)
        dd if="$src" of="$dst.part" bs=64M oflag=direct conv=fsync status=none && mv "$dst.part" "$dst"
        echo "  $(( size / 1048576 / ( $(date +%s) - t0 + 1 ) )) MiB/s"
    done
done < <(grep -v -E '^\s*(#|$)' "$LAB/macos/models.txt")
df -h "$m" | tail -n 1
echo "on macOS: bash $T/linux-lab/macos/collect.sh   (or: ... collect.sh hw for the hardware part alone)"
