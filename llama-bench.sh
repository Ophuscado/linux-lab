#!/usr/bin/env bash
# llama-bench.sh MODEL.gguf: how fast llama.cpp runs on this system, on the CPU and on the
# GPU, into ~/llama-bench-<system>-<kernel release>.txt.
#
# Builds llama.cpp twice under ~/src/llama.cpp (build-cpu, build-gpu) and runs its own
# llama-bench with the same model on both. In Linux the GPU path is Vulkan on the Asahi GPU
# driver, so this needs a kernel with that driver (the stock kernel, or the tbt/7.1 one);
# the file then also holds llama.cpp's per-operation Vulkan timings, which show where the
# time goes. In macOS the GPU path is Metal: run the script there with the same model file
# and the same LLAMA_REF to get the figure Vulkan is compared against (needs the Xcode
# command line tools and cmake).
#
# The first Linux run installs build packages with dnf; nothing else outside
# ~/src/llama.cpp and the output file is touched.
#
# Environment: LLAMA_SRC (source directory), LLAMA_REF (branch, tag or commit to build,
# default: what is checked out, master on a first run), THREADS (CPU threads for the CPU
# run, default: performance cores), BENCH_LABEL (added to the output file name; set by
# mesa-side.sh run).

set -euo pipefail

MODEL=${1:-}
SRC=${LLAMA_SRC:-$HOME/src/llama.cpp}
OS=$(uname -s)
OUT=$HOME/llama-bench-$OS-$(uname -r)${BENCH_LABEL:+-$BENCH_LABEL}.txt

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
sec() { printf '\n===== %s\n' "$*"; }

[[ -n $MODEL && -r $MODEL ]] || die "usage: $0 MODEL.gguf (a model file you already have)"
MODEL=$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL")

if [[ $OS == Linux ]]; then
    GPU_OPTS=(-DGGML_VULKAN=ON)
    # spirv-headers-devel: the Vulkan part of llama.cpp looks for its CMake package.
    missing=()
    for pkg in git-core cmake gcc-c++ make glslc vulkan-headers vulkan-loader-devel vulkan-tools spirv-headers-devel; do
        rpm -q --quiet "$pkg" || missing+=("$pkg")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        sudo dnf install -y "${missing[@]}"
    fi
    JOBS=$(nproc)
else
    GPU_OPTS=(-DGGML_METAL=ON)
    command -v cmake >/dev/null || die "cmake not found (for example: brew install cmake)"
    JOBS=$(sysctl -n hw.ncpu)
fi

if [[ ! -d $SRC/.git ]]; then
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$SRC"
fi
cd "$SRC"
if [[ -n ${LLAMA_REF:-} ]]; then
    git fetch --depth 1 origin "$LLAMA_REF"
    git checkout -q --detach FETCH_HEAD
fi

build() { # $1 directory, rest cmake options
    local dir=$1
    shift
    # Compiler output goes to a log; only a failure shows its end.
    if ! { cmake -S . -B "$dir" -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF "$@" &&
        cmake --build "$dir" --target llama-bench -j"$JOBS"; } >"$dir.log" 2>&1; then
        grep -B2 -A12 -m1 -E 'CMake Error|error:' "$dir.log" || tail -n 25 "$dir.log"
        die "build failed; full log in $SRC/$dir.log"
    fi
    [[ -x $dir/bin/llama-bench ]] || die "no llama-bench in $dir"
}

echo "building the CPU variant"
build build-cpu -DGGML_VULKAN=OFF -DGGML_METAL=OFF
echo "building the GPU variant"
build build-gpu "${GPU_OPTS[@]}"

# The efficiency cores only slow the CPU run down: count the cores of the fastest kind.
if [[ -z ${THREADS:-} ]]; then
    if [[ $OS == Linux ]]; then
        max=$(cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | sort -n | tail -n 1) || true
        THREADS=$(grep -lx "${max:-none}" /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | wc -l) || true
    else
        THREADS=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo 0)
    fi
    [[ $THREADS -gt 0 ]] || THREADS=$JOBS
fi

# Run llama-bench; print what it says about the GPU it picked, then its result table.
bench() { # $1 build directory, rest llama-bench options
    local dir=$1 log
    shift
    log=$(mktemp)
    "$dir/bin/llama-bench" -m "$MODEL" -t "$THREADS" "$@" >"$log" 2>&1 || echo "llama-bench failed"
    grep -E '^ggml_(vulkan|metal)[a-z_]*: .*(=|GPU|device|memory|fp16|matrix|simd|unified)' "$log" | sort -u | head -n 20 || true
    grep -E '^\| |^build:|error|failed' "$log" | tail -n 14 || true
    rm -f "$log"
}

# One short run with llama.cpp's Vulkan timer on: time per kind of operation, summed
# over the run and printed when it ends; largest total first.
profile() { # $1 title, rest llama-bench options
    local log
    sec "vulkan timings, $1"
    shift
    log=$(mktemp)
    GGML_VK_PERF_LOGGER=1 GGML_VK_PERF_LOGGER_FREQUENCY=1000000000 \
        build-gpu/bin/llama-bench -m "$MODEL" -ngl 99 -t "$THREADS" -r 1 --no-warmup "$@" >"$log" 2>&1 ||
        echo "llama-bench failed"
    awk 'match($0, / = [0-9.e+]+ us/) { print substr($0, RSTART + 3, RLENGTH - 6) "\t" $0 }' "$log" |
        sort -gr | cut -f2- | head -n 40 || true
    grep '^Total time' "$log" || echo "no timings in the output"
    rm -f "$log"
}

{
    sec "system"
    uname -sr
    echo "llama.cpp $(git log -1 --format='%H %cd' --date=short)"
    echo "model: $(basename "$MODEL") ($(du -h "$MODEL" | cut -f1))"
    echo "cpu threads: $THREADS of $JOBS"

    if [[ $OS == Linux ]]; then
        lsmod 2>/dev/null | grep -E '^(asahi|apple_dcp|appledrm) ' || echo "no asahi GPU module loaded"
        sec "vulkan device"
        vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverName|driverInfo|apiVersion|deviceType' || echo "no Vulkan device"
    else
        sysctl -n machdep.cpu.brand_string
        sw_vers -productVersion
    fi

    sec "cpu"
    bench build-cpu -ngl 0 -p 512 -n 128 -r 3

    sec "gpu, all layers (${GPU_OPTS[0]#-DGGML_})"
    bench build-gpu -ngl 99 -p 512 -n 128 -r 3

    sec "gpu, all layers, flash attention"
    bench build-gpu -ngl 99 -fa 1 -p 512 -n 128 -r 3

    if [[ $OS == Linux ]]; then
        profile "prompt of 512 tokens" -p 512 -n 0
        profile "generating 64 tokens" -p 0 -n 64
    fi
} 2>&1 | tee "$OUT"

echo
echo "Wrote $OUT. Attach it to the chat."
