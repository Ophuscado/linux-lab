#!/bin/bash
# collect.sh: everything worth measuring in one macOS boot of this Mac, so Linux can be compared with it
# and macOS need not be booted again for it. Run from Terminal in macOS, from this folder:
#
#   ./collect.sh                 all of it (hours: it builds llama.cpp and downloads the models)
#   ./collect.sh hw              only the hardware description (minutes, no downloads)
#   ./collect.sh STEP...         some steps: hw, ane, tbt, gpu, llama, ablate, ops, vulkan, power, re,
#                                input (interactive), smc, anebench, display, vkchain
#   LLAMA_ONLY="qwen" ./collect.sh llama
#                                only those models of models.txt (names as there), e.g. one added later
#   LOCAL=~/models ./collect.sh  copy each model to the internal disk first (one read of the USB disk each)
#   models.env                   beside the models folder: absolute paths of models downloaded on macOS
#                                (QWEN=..., GEMMA_MTP=...); empty names use the copies stage.sh made
#
# Everything lands in ~/linux-lab-macos/<date>/ and, at the end, in one archive beside it. The
# hardware dumps leave out lines naming a serial number, a UUID or a network address, so the
# archive can be published. Nothing on the Mac is changed except what the steps install for
# themselves under ~/linux-lab-macos (a llama.cpp checkout, a Python venv). The models are read
# from where models.env points, else from the exFAT disk both systems share (MODELS, filled from Linux
# by stage.sh); nothing is downloaded.
#
# Steps:
#   hw     sw_vers, sysctl hw/machdep, system_profiler (hardware, displays, PCI, NVMe, USB, power,
#          memory), the IODeviceTree plane, IOService nodes of the GPU, ANE, DCP, SMC
#   ane    the Neural Engine as macOS sees it: its device-tree nodes (both dies), firmware, IOService
#          properties; what omarchy-ane's T6022 overlay is built from
#   tbt    Thunderbolt and USB4: system_profiler, the acio/apciec/atc-phy nodes (kernel/apciec-dump.sh),
#          with the disk boxes plugged in
#   gpu    vk-chain's Metal twin (vk-chain/metal-chain.m): one launch's cost, chained and free, the
#          dependent-FMA clock; the number the Linux generation gap is measured against
#   llama  llama.cpp with Metal at the same upstream commit as the Linux numbers (src-patches/llama.cpp/
#          honeykrisp/BASE): llama-bench pp512/pp2048/tg128, generation after 0-16k tokens of context and the
#          1-512 token batch curve on every model of models.txt, the code-edit speculation test, test-backend-ops perf for MUL_MAT/MUL_MAT_ID
#   ablate per model, Metal's fusion, concurrency and graph reordering off one by one (pp512, tg128),
#          and one token's encoded graph with what was fused
#   vulkan llama.cpp's Vulkan backend through MoltenVK: llama-bench and the matmul perf tests, for Vulkan's
#          own share of the Linux gap (VULKAN_INSTALL=1 lets it brew-install MoltenVK, the loader, headers, shaderc)
#   input  HID properties and acceleration tables, settings, Bluetooth, then a guided list of gestures logged as
#          raw reports, decoded touches and application events (input-log.c; asks for Input Monitoring)
#   smc    every SMC key idle, under full CPU and GPU load, and after (smc-dump.c)
#   anebench  the Neural Engine through Core ML: fp16 adds and matrix-vector timings per compute unit, ane_power
#   display   ColorSync profiles of the displays, framebuffer properties
#   ops    test-backend-ops perf of the non-matmul ops of a generated token (norms, rope, attention, ...)
#   re     every IORegistry plane, kexts, firmware names and hashes, metal-info, Apple's GPU code for the
#          llama.cpp kernels (private/), pmset, every powermetrics sampler, full sysctl and system_profiler
#   power  powermetrics (needs sudo): idle, then during a prompt and during generation
#
# Needs the Command Line Tools (xcode-select --install) for clang and git; cmake comes from pip.
set -uo pipefail
# ioreg and sysctl print raw property bytes that are not UTF-8; BSD sed and grep stop on them ("illegal byte
# sequence") in a UTF-8 locale and leave the file short. Bytes, not characters, here and in the scripts it calls.
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd)
LAB=$(cd "$HERE/.." && pwd)
WORK=${WORK:-$HOME/linux-lab-macos}
OUT=$WORK/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a "$OUT/collect.log"; }
# Lines that would identify this Mac: serial numbers, UUIDs, MAC and IP addresses.
scrub() { grep -v -i -E 'serial|uuid|udid|IOMACAddress|mac-address|local-mac|ip-address|"?(provisioning|ecid|chip-id-?unique)' |
    sed -E 's/([0-9a-f]{2}:){5}[0-9a-f]{2}/<mac>/gI; s/[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}/<uuid>/g'; }
have() { command -v "$1" >/dev/null 2>&1; }

step_hw() {
    log "hw"
    { sw_vers; uname -a; sysctl hw machdep.cpu 2>/dev/null; } | scrub >"$OUT/hw-sysctl.txt"
    system_profiler -detailLevel mini -json SPHardwareDataType SPDisplaysDataType SPPCIDataType SPNVMeDataType \
        SPUSBDataType SPPowerDataType SPMemoryDataType 2>/dev/null | scrub >"$OUT/hw-system-profiler.json"
    ioreg -p IODeviceTree -l -w0 | scrub | gzip >"$OUT/hw-iodevicetree.txt.gz"
    for c in AGXAccelerator AGXFirmwareKextG14XRTBuddy AppleH11ANEInterface H11ANEIn AppleDCP AppleSMC IOPlatformExpertDevice; do
        ioreg -r -l -w0 -c "$c" 2>/dev/null | scrub >"$OUT/hw-ioservice-$c.txt"
    done
    find "$OUT" -name 'hw-ioservice-*' -empty -delete
}

step_ane() {
    log "ane"
    local n
    for n in $(ioreg -p IODeviceTree -w0 | sed -n 's/.*+-o \([^ @<]*\).*/\1/p' | grep -i -E '^ane' | sort -u); do
        ioreg -p IODeviceTree -r -l -w0 -n "$n" | scrub >"$OUT/ane-dt-$n.txt"
    done
    ioreg -r -l -w0 -c H11ANEIn 2>/dev/null | scrub >"$OUT/ane-ioservice.txt"
    ls -la /System/Library/Extensions/AppleH11ANEInterface.kext/Contents 2>/dev/null >"$OUT/ane-kext.txt"
    find /usr/standalone/firmware /System/Library -iname '*ane*fw*' -o -iname 'h1*ane*' 2>/dev/null | head -n 50 >"$OUT/ane-firmware-files.txt"
}

step_tbt() {
    log "tbt (plug the disk boxes in first)"
    system_profiler -detailLevel mini -json SPThunderboltDataType SPUSBDataType 2>/dev/null | scrub >"$OUT/tbt-system-profiler.json"
    # Through bash and with its messages kept: on 28 Oct (macOS 15) this step left no tbt-apciec.txt and said nothing.
    if [[ -f $LAB/kernel/apciec-dump.sh ]]; then
        HOME=$OUT bash "$LAB/kernel/apciec-dump.sh" >"$OUT/tbt-apciec-run.txt" 2>&1 || log "tbt: apciec-dump.sh failed (see tbt-apciec-run.txt)"
        if [[ -f $OUT/apciec.txt ]]; then scrub <"$OUT/apciec.txt" >"$OUT/tbt-apciec.txt" && rm -f "$OUT/apciec.txt"; else log "tbt: apciec-dump.sh wrote nothing"; fi
    else
        log "tbt: no $LAB/kernel/apciec-dump.sh"
    fi
    # Every PCI device macOS sees, with its link: a tunnelled device shows its IOPCITunnelled and link speed here.
    ioreg -r -l -w0 -c IOPCIDevice 2>/dev/null | scrub >"$OUT/tbt-pci-devices.txt"
}

step_gpu() {
    log "gpu: metal-chain"
    local b=$WORK/metal-chain
    clang -O2 -fobjc-arc -framework Metal -framework Foundation "$LAB/gpu/vk-chain/metal-chain.m" -o "$b" 2>"$OUT/gpu-metal-chain-build.txt" ||
        { log "metal-chain does not build (see gpu-metal-chain-build.txt)"; return; }
    "$b" >"$OUT/gpu-metal-chain.txt" 2>&1 || log "metal-chain failed (see gpu-metal-chain.txt)"
}

# Everything a driver or reverse-engineering session may need later, so macOS need not be booted for it:
# every IORegistry plane, loaded kexts, firmware file names and hashes (not the files), Metal's view of the GPU
# (metal-info), Apple's GPU code for llama.cpp's kernels (metal-archive, and Metal's own shader cache after the
# llama runs: both under private/, Apple's compiler output, for study, not for publishing), power management
# settings, every powermetrics sampler, the full sysctl and system_profiler.
step_re() {
    log "re"
    local p
    for p in IOService IODeviceTree IOPower IOUSB IOAudio IOFireWire; do
        ioreg -l -w0 -p "$p" 2>/dev/null | scrub | gzip >"$OUT/re-ioreg-$p.txt.gz"
    done
    kmutil showloaded --list-only 2>/dev/null >"$OUT/re-kexts.txt" || kextstat >"$OUT/re-kexts.txt" 2>&1
    { for d in /usr/standalone/firmware /System/Library/Extensions/*.kext/Contents/Resources /System/Volumes/Preboot/*/restore/Firmware; do
          find "$d" -type f \( -iname '*.im4p' -o -iname '*.bin' -o -iname '*.fw' -o -iname '*firmware*' \) 2>/dev/null
      done | sort -u | while read -r f; do printf '%s  %s  %s\n' "$(shasum -a 256 "$f" | cut -c1-64)" "$(stat -f %z "$f")" "$f"; done; } >"$OUT/re-firmware.txt" 2>/dev/null
    clang -O2 -fobjc-arc -framework Metal -framework Foundation "$HERE/metal-info.m" -o "$WORK/metal-info" 2>"$OUT/re-metal-info-build.txt" &&
        "$WORK/metal-info" >"$OUT/re-metal-info.txt" 2>&1
    { pmset -g; pmset -g custom; pmset -g cap; pmset -g therm; pmset -g assertions; } 2>&1 | scrub >"$OUT/re-pmset.txt"
    sysctl -a 2>/dev/null | scrub | gzip >"$OUT/re-sysctl.txt.gz"
    system_profiler -detailLevel full 2>/dev/null | scrub | gzip >"$OUT/re-system-profiler-full.txt.gz"
    powermetrics -h 2>&1 | sed -n '/samplers/,/^$/p' >"$OUT/re-powermetrics-samplers.txt"
    if sudo -n true 2>/dev/null || sudo -v; then
        sudo powermetrics --samplers all -i 1000 -n 5 2>&1 | scrub >"$OUT/re-powermetrics-all.txt"
    fi
    if [[ -n ${B:-} || -d $WORK/llama.cpp/build ]]; then
        # One self-contained source per kernel family since llama.cpp split its Metal kernels (2026: kernels/*.metal,
        # embedded as autogenerated/ggml-metal-embed-KIND.metal); the single ggml-metal-embed.metal of before is gone,
        # which is why the 28 Oct run archived nothing. Kernels that need function constants are listed, not archived:
        # their compiled forms are in Metal's shader cache below, as the llama runs specialized them.
        mkdir -p "$OUT/private"
        if clang -O2 -fobjc-arc -framework Metal -framework Foundation "$HERE/metal-archive.m" -o "$WORK/metal-archive" 2>"$OUT/re-metal-archive-build.txt"; then
            local m k n=0
            while IFS= read -r m; do
                k=$(basename "$m" .metal); k=${k#ggml-metal-embed}; k=${k#-}; k=${k:-all}
                { echo "== $k"; "$WORK/metal-archive" "$m" "$OUT/private/ggml-$k.metallib"; } >>"$OUT/re-metal-archive.txt" 2>&1
                n=$((n + 1))
            done < <(find "$WORK/llama.cpp/build" -name 'ggml-metal-embed*.metal' | sort)
            ((n)) || log "re: no ggml-metal-embed*.metal under $WORK/llama.cpp/build: Apple's code for the kernels not archived"
        fi
        local c; c=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)com.apple.metal
        [[ -d $c ]] && tar -czf "$OUT/private/metal-shader-cache.tar.gz" -C "$c" . 2>/dev/null
    fi
}

venv() {
    [[ -x $WORK/venv/bin/python ]] || python3 -m venv "$WORK/venv"
    "$WORK/venv/bin/pip" -q install --upgrade pip cmake ninja >/dev/null
    PATH=$WORK/venv/bin:$PATH
}

build_llama() {
    local base
    base=$(sed -n 's/^BASE=\([0-9a-f]*\).*/\1/p' "$LAB/src-patches/llama.cpp/honeykrisp/BASE")
    local s=$WORK/llama.cpp
    [[ -d $s/.git ]] || git clone -q https://github.com/ggml-org/llama.cpp "$s"
    git -C "$s" fetch -q origin "$base" && git -C "$s" checkout -q "$base"
    cmake -S "$s" -B "$s/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DLLAMA_CURL=OFF \
        -DLLAMA_BUILD_TESTS=ON >"$OUT/llama-cmake.txt" 2>&1 &&
        cmake --build "$s/build" --target llama-bench llama-server test-backend-ops >>"$OUT/llama-cmake.txt" 2>&1
    echo "$base" >"$OUT/llama-commit.txt"
    B=$s/build/bin
}

# models.txt: NAME|FILE|MTP_FILE under $MODELS (blank lines and # comments skipped)
MODELS=${MODELS:-/Volumes/BACKUP/linux-lab-macos/models}
# models.env (MODELS_ENV, default beside the models folder; stage.sh writes it with every name empty and the
# metadata of the Linux files in comments): NAME=/absolute/path and NAME_MTP=/absolute/path, NAME in capitals as
# in models.txt (QWEN, GEMMA_MTP). Empty or absent: $MODELS/FILE as staged from Linux. A model split in parts is
# given by its first part (...-00001-of-0000N.gguf); llama.cpp loads the others from beside it. Read as data,
# never sourced.
MODELS_ENV=${MODELS_ENV:-$(dirname "$MODELS")/models.env}
envpath() {
    [[ -f $MODELS_ENV ]] || return 0
    local v
    v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$MODELS_ENV" | tail -n 1 |
        sed -E "s/[[:space:]]+\$//; s/^\"(.*)\"\$/\\1/; s/^'(.*)'\$/\\1/")
    case $v in "~/"*) v=$HOME/${v#\~/} ;; esac
    printf '%s' "$v"
}
# model_path NAME FILE [_MTP]: the file to load, from models.env or the staged copy; nothing when neither names one.
model_path() {
    local k v
    k=$(printf '%s%s' "$1" "${3:-}" | tr '[:lower:]' '[:upper:]'); v=$(envpath "$k")
    [[ -n $v || -n $2 ]] || return 0
    printf '%s\n' "${v:-$MODELS/$2}"
}
# Every file of a model: the parts beside a -00001-of-N file, or the file itself.
parts() {
    case $1 in
    *-00001-of-*.gguf) ls "${1%-00001-of-*}"-[0-9][0-9][0-9][0-9][0-9]-of-*.gguf ;;
    *) printf '%s\n' "$1" ;;
    esac
}
# LOCAL=DIR: copy each model (all its parts) into DIR/KEY before its runs (one read of the slow USB disk per file;
# each file is loaded about six times: two llama-bench runs and a server per speculation setting), and delete the
# copy after them unless KEEP_LOCAL=1. Without LOCAL the files are read where they are each time, which the page
# cache absorbs only while the model and its cached copy both fit in memory.
LOCAL=${LOCAL:-} KEEP_LOCAL=${KEEP_LOCAL:-0}
# fetch KEY PATH: the path to load: PATH, or its copy under $LOCAL/KEY, made now if needed.
fetch() {
    [[ -n $LOCAL ]] || { printf '%s\n' "$2"; return; }
    local d=$LOCAL/$1 p need=0 avail
    while IFS= read -r p; do need=$((need + $(stat -f %z "$p"))); done < <(parts "$2")
    if [[ ! -f $d/$(basename "$2") ]]; then
        mkdir -p "$d"
        avail=$(( $(df -k "$LOCAL" | awk 'NR==2 {print $4}') * 1024 ))
        ((avail - need > 20 * 1024 * 1024 * 1024)) || { log "no room in $LOCAL for $2; reading it where it is" >&2; printf '%s\n' "$2"; return; }
        while IFS= read -r p; do
            cp "$p" "$d/$(basename "$p").part" && mv "$d/$(basename "$p").part" "$d/$(basename "$p")"
        done < <(parts "$2")
    fi
    printf '%s\n' "$d/$(basename "$2")"
}
drop() { [[ -n $LOCAL && -n $1 && $KEEP_LOCAL != 1 ]] && rm -rf "${LOCAL:?}/$1"; return 0; }
models() { grep -v -E '^\s*(#|$)' "$HERE/models.txt"; }

step_llama() {
    log "llama: build"
    venv; build_llama; [[ -x $B/llama-bench ]] || { log "llama.cpp did not build (see llama-cmake.txt)"; return; }
    local name file mtp f
    while IFS='|' read -r name file mtp; do
        [[ -z ${LLAMA_ONLY:-} || " $LLAMA_ONLY " == *" $name "* ]] || continue
        f=$(model_path "$name" "$file")
        [[ -f $f ]] || { log "llama: $name: $f is not there (set $(echo "$name" | tr '[:lower:]' '[:upper:]')= in $MODELS_ENV, or macos/stage.sh copies it); skipped"; continue; }
        local m mf=""; m=$(model_path "$name" "$mtp" _MTP)
        [[ -z $m || -f $m ]] || { log "llama: $name: MTP file $m is not there; its MTP run skipped"; m=""; }
        log "llama: $name: $f${m:+ with $m}${LOCAL:+, copied to $LOCAL first}"
        f=$(fetch "$name" "$f"); [[ -n $m ]] && mf=$(fetch "${name}_mtp" "$m")
        "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512,2048 -n 128 -r 3 -o json >"$OUT/llama-$name-bench.json" 2>>"$OUT/llama-errors.txt"
        "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 0 -n 32 -d 0,1024,4096,16384 -r 2 -o json \
            >"$OUT/llama-$name-depth.json" 2>>"$OUT/llama-errors.txt"
        "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 8192 -b 8192 -p 1,2,4,8,9,12,16,24,32,48,64,128,512 -n 0 -r 2 -o json \
            >"$OUT/llama-$name-batches.json" 2>>"$OUT/llama-errors.txt"
        spec "$name" "$f" "$mf"
        drop "$name"; drop "${mf:+${name}_mtp}"
    done < <(models)
    log "llama: test-backend-ops perf"
    "$B/test-backend-ops" perf -b MTL0 -o MUL_MAT >"$OUT/llama-ops-mul_mat.txt" 2>&1
    "$B/test-backend-ops" perf -b MTL0 -o MUL_MAT_ID >"$OUT/llama-ops-mul_mat_id.txt" 2>&1
}

# What Metal's own graph work is worth, per model: fusion, concurrent dispatch and the graph reordering switched
# off one by one and all together (pp512 and tg128, 3 runs each), then one token's graph as Metal encodes it
# (GGML_METAL_GRAPH_DEBUG, FUSION_DEBUG, printed at debug level, so llama-bench -v): its op count and what was fused. The Vulkan side has none of these on
# Honeykrisp, so this is the share of the generation gap launch fusion could close.
step_ablate() {
    log "ablate: build"
    venv; [[ -x ${B:-}/llama-bench ]] || build_llama; [[ -x $B/llama-bench ]] || { log "llama.cpp did not build"; return; }
    local name file mtp f c
    while IFS='|' read -r name file mtp; do
        [[ -z ${LLAMA_ONLY:-} || " $LLAMA_ONLY " == *" $name "* ]] || continue
        f=$(model_path "$name" "$file"); [[ -f $f ]] || continue
        log "ablate: $name"
        for c in default GGML_METAL_FUSION_DISABLE GGML_METAL_CONCURRENCY_DISABLE GGML_METAL_GRAPH_OPTIMIZE_DISABLE all; do
            case $c in
            default) env "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512 -n 128 -r 3 -o json ;;
            all) env GGML_METAL_FUSION_DISABLE=1 GGML_METAL_CONCURRENCY_DISABLE=1 GGML_METAL_GRAPH_OPTIMIZE_DISABLE=1 \
                "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512 -n 128 -r 3 -o json ;;
            *) env "$c=1" "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512 -n 128 -r 3 -o json ;;
            esac >"$OUT/ablate-$name-$c.json" 2>>"$OUT/ablate-errors.txt"
        done
        GGML_METAL_GRAPH_DEBUG=2 GGML_METAL_FUSION_DEBUG=2 "$B/llama-bench" -v -m "$f" -ngl 99 -fa 1 -p 0 -n 1 -r 1 \
            2>&1 | head -c 50000000 | gzip >"$OUT/ablate-$name-graph.txt.gz"
    done < <(models)
}

# llama.cpp's Vulkan backend on this Mac through MoltenVK (Vulkan over Metal), same commit and settings as the
# llama step: the same Vulkan shaders as on Linux, compiled by Apple's compiler and run by Apple's driver. Near the
# Metal numbers: the shaders and graph are fine and the gap on Linux is the driver stack; far from them: llama.cpp's
# Vulkan path is part of the gap. Needs Homebrew's molten-vk vulkan-loader vulkan-headers shaderc spirv-headers
# vulkan-tools (installed only
# when VULKAN_INSTALL=1; otherwise the step says what is missing).
step_vulkan() {
    log "vulkan"
    have brew || { log "vulkan: no Homebrew; skipped"; return; }
    local pkgs="molten-vk vulkan-loader vulkan-headers shaderc spirv-headers vulkan-tools" p missing="" hb icd
    for p in $pkgs; do brew list --versions "$p" >/dev/null 2>&1 || missing+="$p "; done
    if [[ -n $missing ]]; then
        [[ ${VULKAN_INSTALL:-0} == 1 ]] || { log "vulkan: missing $missing(VULKAN_INSTALL=1 installs them with brew); skipped"; return; }
        brew install $missing >"$OUT/vk-brew.txt" 2>&1 || { log "vulkan: brew install failed (see vk-brew.txt)"; return; }
    fi
    hb=$(brew --prefix)
    icd=$(find "$hb/etc/vulkan" "$hb/share/vulkan" "$hb/opt/molten-vk" -name 'MoltenVK_icd.json' 2>/dev/null | head -n 1)
    [[ -n $icd ]] || { log "vulkan: no MoltenVK_icd.json under $hb; skipped"; return; }
    export VK_DRIVER_FILES=$icd VK_ICD_FILENAMES=$icd
    { brew list --versions $pkgs; "$hb/bin/vulkaninfo" --summary 2>&1 || true; } | scrub >"$OUT/vk-info.txt"
    venv; [[ -d $WORK/llama.cpp/.git ]] || build_llama
    local s=$WORK/llama.cpp base
    base=$(sed -n 's/^BASE=\([0-9a-f]*\).*/\1/p' "$LAB/src-patches/llama.cpp/honeykrisp/BASE")
    git -C "$s" checkout -q "$base" 2>/dev/null || { git -C "$s" fetch -q origin "$base" && git -C "$s" checkout -q "$base"; }
    PATH=$hb/bin:$PATH cmake -S "$s" -B "$s/build-vk" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$hb" \
        -DGGML_METAL=OFF -DGGML_VULKAN=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=ON >"$OUT/vk-cmake.txt" 2>&1 &&
        PATH=$hb/bin:$PATH cmake --build "$s/build-vk" --target llama-bench test-backend-ops >>"$OUT/vk-cmake.txt" 2>&1 ||
        { log "vulkan: llama.cpp with Vulkan did not build (see vk-cmake.txt)"; return; }
    local V=$s/build-vk/bin name file mtp f
    while IFS='|' read -r name file mtp; do
        [[ -z ${LLAMA_ONLY:-} || " $LLAMA_ONLY " == *" $name "* ]] || continue
        f=$(model_path "$name" "$file"); [[ -f $f ]] || continue
        log "vulkan: $name"
        "$V/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512,2048 -n 128 -r 3 -o json >"$OUT/vk-$name-bench.json" 2>>"$OUT/vk-errors.txt"
    done < <(models)
    "$V/test-backend-ops" perf -b Vulkan0 -o MUL_MAT >"$OUT/vk-ops-mul_mat.txt" 2>&1
    "$V/test-backend-ops" perf -b Vulkan0 -o MUL_MAT_ID >"$OUT/vk-ops-mul_mat_id.txt" 2>&1
}

# Input devices as macOS drives them: their HID properties (report descriptors, the pointer and scroll acceleration
# tables macOS applies), the user's settings, the Bluetooth view, then input-log for a list of gestures, each
# recorded for its seconds after Enter (s skips one, q ends): raw reports, decoded touches and the events
# applications got, on one clock. For hid-magicmouse, hid-apple and libinput settings on Linux.
INPUT_GESTURES=(
    "mouse-idle|Magic Mouse: hands off|4"
    "mouse-move|Magic Mouse: move it holding its sides, no finger on top|8"
    "mouse-rest-move|Magic Mouse: one finger resting on top, move the mouse around|10"
    "mouse-scroll|Magic Mouse: one finger, scroll slowly up and down, then faster|10"
    "mouse-flick|Magic Mouse: three quick flicks up, lifting the finger each time, let the page coast|10"
    "mouse-hscroll|Magic Mouse: one finger, scroll left and right (the gesture, whether or not the page moves)|8"
    "mouse-swipe2|Magic Mouse: two fingers, swipe left and right|8"
    "mouse-tap1|Magic Mouse: one-finger double tap (smart zoom), three times|8"
    "mouse-tap2|Magic Mouse: two-finger double tap (Mission Control), twice|8"
    "mouse-click|Magic Mouse: left click, right click, three each|8"
    "tp-move|Trackpad: one finger, move the pointer slowly, then fast across|8"
    "tp-tap|Trackpad: tap, then two-finger tap, three each|8"
    "tp-click|Trackpad: press to click, then force click (press harder), three each|10"
    "tp-scroll|Trackpad: two fingers, scroll slowly, then flick and let it coast|10"
    "tp-pinch|Trackpad: pinch in and out|8"
    "tp-rotate|Trackpad: two fingers, rotate|8"
    "tp-swipe3|Trackpad: three fingers, swipe left, right, up, down|10"
    "tp-swipe4|Trackpad: four fingers, swipe left, right, up, down; then five-finger pinch|10"
    "tp-palm|Trackpad: rest the palm's edge on it and move one finger|8"
    "tp-drag|Trackpad: click and hold, drag a window, release|8"
    "kb-frow|Keyboard: F1 to F12 once each, then Fn+F1 to Fn+F12|20"
    "kb-fn|Keyboard: Fn alone (Globe), Fn+arrows, Fn+Delete, Fn+E, Fn+F, Fn+C, Fn+A, Fn+N, Fn+Q|20"
    "kb-mods|Keyboard: Caps Lock twice, each modifier alone (both sides), Cmd+Tab, Cmd+Space then Escape|15"
)
step_input() {
    log "input"
    ioreg -r -l -w0 -c IOHIDDevice 2>/dev/null | scrub >"$OUT/input-ioreg-hid.txt"
    ioreg -r -l -w0 -c AppleMultitouchDevice 2>/dev/null | scrub >"$OUT/input-ioreg-multitouch.txt"
    ioreg -r -l -w0 -c IOHIDEventService 2>/dev/null | scrub | gzip >"$OUT/input-ioreg-eventservice.txt.gz"
    { hidutil list 2>&1 | scrub
      for k in HIDPointerAcceleration HIDMouseAcceleration HIDTrackpadAcceleration HIDScrollAcceleration HIDMouseScrollAcceleration \
          HIDTrackpadScrollAcceleration HIDPointerAccelerationType HIDKeyRepeat HIDInitialKeyRepeat HIDFKeyMode HIDScrollReverse; do
          echo "== $k"; hidutil property --get "$k" 2>&1
      done; } >"$OUT/input-hidutil.txt"
    system_profiler -detailLevel full SPBluetoothDataType 2>/dev/null | scrub >"$OUT/input-bluetooth.txt"
    python3 -I "$HERE/ux-defaults.py" >"$OUT/input-ux-defaults.txt" 2>&1
    clang -O2 "$HERE/input-log.c" -o "$WORK/input-log" -framework CoreFoundation -framework IOKit -framework ApplicationServices \
        2>"$OUT/input-log-build.txt" || { log "input: input-log did not build (see input-log-build.txt)"; return; }
    # INPUT_ONLY="mouse-flick tp-scroll" records only those. Each one runs from Enter until Ctrl+C (repeat the gesture
    # as often as you like meanwhile); INPUT_TIMED=1 uses the listed seconds instead.
    echo "Enter starts a gesture, Ctrl+C ends it (repeat it several times meanwhile); s skips it, q ends the list."
    echo "Type only the keys a keyboard prompt asks for."
    local g lab what secs a
    trap ':' INT
    for g in "${INPUT_GESTURES[@]}"; do
        IFS='|' read -r lab what secs <<<"$g"
        [[ -z ${INPUT_ONLY:-} || " $INPUT_ONLY " == *" $lab "* ]] || continue
        read -r -p "[$lab] $what - Enter, s or q: " a </dev/tty
        [[ $a == q ]] && break
        [[ $a == s ]] && continue
        [[ ${INPUT_TIMED:-0} == 1 ]] || secs=0
        "$WORK/input-log" "$OUT/input-log.tsv" "$secs" "$lab" | tee -i -a "$OUT/input-log-counts.txt"
    done
    trap - INT
    [[ -f $OUT/input-log.tsv ]] && gzip -f "$OUT/input-log.tsv"
}

# The SMC's keys idle and under load (all CPU cores busy and metal-chain on the GPU), for the Linux sensor map.
step_smc() {
    log "smc"
    clang -O2 "$HERE/smc-dump.c" -o "$WORK/smc-dump" -framework IOKit -framework CoreFoundation 2>"$OUT/smc-build.txt" ||
        { log "smc: smc-dump did not build (see smc-build.txt)"; return; }
    "$WORK/smc-dump" >"$OUT/smc-idle.tsv" 2>&1
    local pids=() i
    for ((i = 0; i < $(sysctl -n hw.ncpu); i++)); do yes >/dev/null & pids+=($!); done
    if clang -O2 -fobjc-arc -framework Metal -framework Foundation "$LAB/gpu/vk-chain/metal-chain.m" -o "$WORK/metal-chain" 2>/dev/null; then
        "$WORK/metal-chain" >/dev/null 2>&1 & pids+=($!)
    fi
    sleep 25
    "$WORK/smc-dump" >"$OUT/smc-load.tsv" 2>&1
    kill "${pids[@]}" 2>/dev/null; wait 2>/dev/null
    sleep 30
    "$WORK/smc-dump" >"$OUT/smc-after.tsv" 2>&1
}

# The Neural Engine through Core ML (ane-bench.py), with powermetrics' ane_power sampled meanwhile, and the compiled
# programs macOS cached for it (Apple's compiler output: under private/, for study, not for publishing).
step_anebench() {
    log "anebench: coremltools into the venv"
    venv; "$WORK/venv/bin/pip" -q install coremltools numpy >"$OUT/ane-pip.txt" 2>&1 || { log "anebench: pip failed (see ane-pip.txt)"; return; }
    local mark=$WORK/ane-start pm=""
    touch "$mark"
    if sudo -v; then
        sudo powermetrics --samplers ane_power,gpu_power,cpu_power -i 500 >"$OUT/ane-powermetrics.txt" 2>&1 & pm=$!
    fi
    "$WORK/venv/bin/python" "$HERE/ane-bench.py" "$OUT" 2>&1 | tee "$OUT/ane-bench.txt"
    [[ -n $pm ]] && { sudo kill "$pm" 2>/dev/null; wait "$pm" 2>/dev/null; }
    mkdir -p "$OUT/private"
    local c; c=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null)
    # Every file written meanwhile wherever Core ML and aned cache (the whole list kept); archived without the weights
    # (weight.bin, copies of the models: 196 MB on 28 Oct) so only the compiled programs and their metadata remain.
    sudo find /private/var/folders /private/var/db /Library/Caches "$HOME/Library/Caches" -xdev -newer "$mark" -type f 2>/dev/null |
        grep -v -E '/linux-lab-macos/' >"$OUT/ane-new-files.txt"
    grep -i -E 'ane|e5|hwx|espresso|mlmodelc|coreml' "$OUT/ane-new-files.txt" | grep -v '/weights/weight\.bin$' >"$OUT/ane-cache-files.txt"
    [[ -s $OUT/ane-cache-files.txt ]] && sudo tar -czf "$OUT/private/ane-compiled.tar.gz" -T "$OUT/ane-cache-files.txt" 2>/dev/null &&
        sudo chown "$(id -u)" "$OUT/private/ane-compiled.tar.gz"
}

# The colour profiles macOS made or uses for the displays (the LG TV's included), for KDE's colour management.
step_display() {
    log "display"
    mkdir -p "$OUT/private/colorsync"
    { ls -la /Library/ColorSync/Profiles/Displays "$HOME/Library/ColorSync/Profiles" /System/Library/ColorSync/Profiles 2>&1; } >"$OUT/display-colorsync.txt"
    cp /Library/ColorSync/Profiles/Displays/*.icc "$HOME"/Library/ColorSync/Profiles/*.ic[cm] "$OUT/private/colorsync/" 2>/dev/null
    ioreg -r -l -w0 -c IOMobileFramebuffer 2>/dev/null | scrub | gzip >"$OUT/display-framebuffer.txt.gz"
    system_profiler -detailLevel full SPDisplaysDataType 2>/dev/null | scrub >"$OUT/display-profiler.txt"
}

# vk-chain, the launch and shader microbenchmarks of the Linux runs, on MoltenVK: the same Vulkan launches on Apple's
# driver, between metal-chain (Metal, 2.27 us per dependent launch) and Honeykrisp (4.0-4.2 us), so the launch cost
# splits into what Vulkan's model costs and what Mesa adds. Needs the vulkan step's Homebrew packages.
step_vkchain() {
    log "vkchain"
    have brew || { log "vkchain: no Homebrew; skipped"; return; }
    local hb icd c; hb=$(brew --prefix)
    icd=$(find "$hb/etc/vulkan" "$hb/share/vulkan" "$hb/opt/molten-vk" -name 'MoltenVK_icd.json' 2>/dev/null | head -n 1)
    [[ -n $icd ]] || { log "vkchain: no MoltenVK_icd.json under $hb; skipped"; return; }
    export VK_DRIVER_FILES=$icd VK_ICD_FILENAMES=$icd
    PATH=$hb/bin:$PATH bash "$LAB/gpu/vk-chain/vk-chain.sh" build >"$OUT/vkchain-build.txt" 2>&1 || { log "vkchain: build failed (see vkchain-build.txt)"; return; }
    for c in run switch dot clock groups barriers latency; do
        log "vkchain: $c"
        PATH=$hb/bin:$PATH bash "$LAB/gpu/vk-chain/vk-chain.sh" "$c" >"$OUT/vkchain-$c.txt" 2>&1
    done
}

# test-backend-ops perf of the other ops one generated token runs (MUL_MAT and MUL_MAT_ID are in the llama step):
# norms, rope, attention, the elementwise and MoE routing ops, copies into the KV cache.
step_ops() {
    log "ops: build"
    venv; [[ -x ${B:-}/test-backend-ops ]] || build_llama; [[ -x $B/test-backend-ops ]] || { log "llama.cpp did not build"; return; }
    local o
    for o in RMS_NORM NORM ROPE FLASH_ATTN_EXT SOFT_MAX GLU UNARY ADD MUL ADD_ID GET_ROWS SET_ROWS CPY CONT ARGSORT TOP_K \
        SUM_ROWS SCALE CONCAT SSM_CONV GATED_DELTA_NET; do
        log "ops: $o"
        "$B/test-backend-ops" perf -b MTL0 -o "$o" >"$OUT/ops-$o.txt" 2>&1
    done
}

# The code edit of the Linux runs (rename a variable in llama-run.sh, greedy): none, ngram-mod 64 and 128,
# and the model's MTP head when it has one.
spec() {
    local name=$1 f=$2 mtp=$3 c s i
    for c in "none|" "ngram-mod-64|--spec-type ngram-mod" \
        "ngram-mod-128|--spec-type ngram-mod --spec-ngram-mod-n-max 128 --spec-ngram-mod-n-min 96" \
        ${mtp:+"mtp|--spec-type draft-mtp -md $mtp -ngld 99"}; do
        "$B/llama-server" -m "$f" ${c#*|} -ngl all -fa on -np 1 -c 16384 -ub 8192 -b 8192 -ctk q8_0 -ctv q8_0 \
            --host 127.0.0.1 --port 8099 >"$OUT/llama-server.log" 2>&1 &
        s=$!
        for ((i = 0; i < 300; i++)); do curl -sf http://127.0.0.1:8099/health >/dev/null && break; sleep 1; done
        echo "$name ${c%%|*}: $("$WORK/venv/bin/python" "$HERE/spec-req.py" 8099 "$LAB/gpu/llama-run.sh" 2>&1 | tail -n 1)" >>"$OUT/llama-spec.txt"
        kill "$s"; wait "$s" 2>/dev/null
    done
}

step_power() {
    log "power: powermetrics asks for your password"
    sudo -v || { log "no sudo: power skipped"; return; }
    sudo powermetrics --samplers cpu_power,gpu_power,ane_power,thermal -i 1000 -n 15 >"$OUT/power-idle.txt" 2>&1
    venv; [[ -x ${B:-}/llama-bench ]] || build_llama
    local f; f=$(model_path qwen "$(models | sed -n 's/^qwen|\([^|]*\)|.*/\1/p')")
    [[ -f $f ]] || f=$(model_path llama2 "$(models | sed -n 's/^llama2|\([^|]*\)|.*/\1/p')")
    [[ -f $f ]] || { log "no model for the power runs"; return; }
    sudo powermetrics --samplers cpu_power,gpu_power,ane_power -i 1000 -n 20 >"$OUT/power-prompt.txt" 2>&1 &
    "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -p 2048 -n 0 -r 8 >/dev/null 2>&1; wait
    sudo powermetrics --samplers cpu_power,gpu_power,ane_power -i 1000 -n 20 >"$OUT/power-generation.txt" 2>&1 &
    "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -p 0 -n 512 -r 2 >/dev/null 2>&1; wait
    echo "$f" >"$OUT/power-model.txt"
}

steps=("$@"); ((${#steps[@]})) || steps=(hw ane tbt gpu llama ablate ops re power)
log "collect.sh: ${steps[*]} into $OUT"
for s in "${steps[@]}"; do
    declare -F "step_$s" >/dev/null || { log "unknown step $s"; continue; }
    "step_$s"
done
tar -czf "$OUT.tar.gz" -C "$WORK" "$(basename "$OUT")"
log "done: $OUT.tar.gz"
[[ -d /Volumes/BACKUP ]] && mkdir -p /Volumes/BACKUP/linux-lab-macos/results && cp "$OUT.tar.gz" /Volumes/BACKUP/linux-lab-macos/results/ &&
    log "copied to /Volumes/BACKUP/linux-lab-macos/results/ for Linux to read"
