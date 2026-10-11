#!/usr/bin/env bash
# llama-bench.sh MODEL.gguf: how fast llama.cpp runs on this kernel, on the CPU and on the
# GPU through Vulkan, into ~/llama-bench-<kernel release>.txt.
#
# Builds llama.cpp twice under ~/src/llama.cpp (build-cpu, build-vulkan) and runs its own
# llama-bench with the same model on both. Linux has no Metal: Vulkan on the Asahi GPU
# driver is the GPU path, so this needs a kernel with that driver (the stock kernel, or
# the tbt/7.1 one). The first run installs build packages with dnf; nothing else outside
# ~/src/llama.cpp and the output file is touched.
#
# Environment: LLAMA_SRC (source directory), LLAMA_REF (git ref to build, default master),
# THREADS (CPU threads for the CPU run, default: performance cores).

set -euo pipefail

MODEL=${1:-}
SRC=${LLAMA_SRC:-$HOME/src/llama.cpp}
REF=${LLAMA_REF:-master}
OUT=$HOME/llama-bench-$(uname -r).txt

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
sec() { printf '\n===== %s\n' "$*"; }

[[ -n $MODEL && -r $MODEL ]] || die "usage: $0 MODEL.gguf (a model file you already have)"

if ! command -v cmake >/dev/null || ! command -v glslc >/dev/null || ! command -v vulkaninfo >/dev/null; then
    sudo dnf install -y git-core cmake gcc-c++ make glslc vulkan-headers vulkan-loader-devel vulkan-tools
fi

if [[ ! -d $SRC/.git ]]; then
    git clone --depth 1 --branch "$REF" https://github.com/ggml-org/llama.cpp "$SRC"
fi
cd "$SRC"

build() { # $1 directory, rest cmake options
    local dir=$1
    shift
    cmake -S . -B "$dir" -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF "$@" >/dev/null
    cmake --build "$dir" --target llama-bench -j"$(nproc)" >/dev/null
    [[ -x $dir/bin/llama-bench ]] || die "no llama-bench in $dir"
}

echo "building the CPU variant"
build build-cpu -DGGML_VULKAN=OFF
echo "building the Vulkan variant"
build build-vulkan -DGGML_VULKAN=ON

# The efficiency cores only slow the CPU run down: count the cores of the fastest kind.
if [[ -z ${THREADS:-} ]]; then
    max=$(cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | sort -n | tail -n 1)
    THREADS=$(grep -lx "${max:-none}" /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq 2>/dev/null | wc -l)
    [[ $THREADS -gt 0 ]] || THREADS=$(nproc)
fi

{
    sec "system"
    uname -r
    echo "llama.cpp $(git log -1 --format='%h %cd' --date=short)"
    echo "model: $(basename "$MODEL") ($(du -h "$MODEL" | cut -f1))"
    echo "cpu threads: $THREADS of $(nproc)"
    lsmod | grep -E '^(asahi|apple_dcp|appledrm) ' || echo "no asahi GPU module loaded"

    sec "vulkan device"
    vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverName|driverInfo|apiVersion|deviceType' || echo "no Vulkan device"

    sec "cpu"
    build-cpu/bin/llama-bench -m "$MODEL" -ngl 0 -t "$THREADS" -p 512 -n 128 -r 3 2>&1 | tail -n 12

    sec "vulkan, all layers on the GPU"
    build-vulkan/bin/llama-bench -m "$MODEL" -ngl 99 -t "$THREADS" -p 512 -n 128 -r 3 2>&1 | tail -n 12
} 2>&1 | tee "$OUT"

echo
echo "Wrote $OUT. Attach it to the chat."
