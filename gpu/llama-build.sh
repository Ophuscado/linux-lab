#!/usr/bin/env bash
# llama-build.sh [deps]: build the honeykrisp-patched llama.cpp the results and llama-run.sh/
# llama-compare.sh measure, at src/llama.cpp-simd/build/bin (llama-bench, llama-server,
# test-backend-ops). Nothing else runs this clone+patch+build step today: llama-bench.sh and
# macos/collect.sh each build a separate, unpatched llama.cpp of their own for comparison.
#
# Clones ggml-org/llama.cpp at src-patches/llama.cpp/honeykrisp/BASE's pinned commit, applies
# that series with git am (one commit per patch, a build identity, never the operator's), then
# a Release Vulkan build (the same cmake flags as macos/collect.sh's Vulkan comparison build).
# .lab-state records the commit and a hash of the patch files, so a changed series or a moved
# BASE re-applies and rebuilds; an unrelated change here does not touch it.
#
# "llama-build.sh deps" only installs the Fedora build packages.

set -euo pipefail

LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SERIES=$LAB/src-patches/llama.cpp/honeykrisp
SRC=$LAB/src/llama.cpp-simd

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

install_packages() {
    local missing=() pkg
    for pkg in git-core cmake gcc-c++ make glslc vulkan-headers vulkan-loader-devel vulkan-tools spirv-headers-devel; do
        rpm -q --quiet "$pkg" || missing+=("$pkg")
    done
    [[ ${#missing[@]} -eq 0 ]] || sudo dnf install -y "${missing[@]}"
}

if [[ ${1:-} == deps ]]; then
    [[ $(uname -s) == Linux ]] || die "deps installs Fedora packages; in macOS install cmake yourself"
    install_packages
    exit 0
fi

[[ $(uname -s) == Linux ]] || die "builds the Vulkan backend; macOS has its own build in macos/collect.sh"
install_packages

# shellcheck disable=SC1091
source "$SERIES/BASE" # UPSTREAM, BASE (the pinned commit), FORK, BRANCH, CLONE

mkdir -p "$(dirname "$SRC")"
if [[ ! -d $SRC/.git ]]; then
    git init -q "$SRC"
    git -C "$SRC" remote add origin "$UPSTREAM"
fi
cd "$SRC"

want="$BASE $(cat "$SERIES"/[0-9][0-9][0-9][0-9]-*.patch | sha256sum | cut -c1-16)"
if [[ $(cat .lab-state 2>/dev/null) != "$want" ]]; then
    if ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
        echo "fetching llama.cpp at ${BASE:0:12}"
        git fetch -q --depth 1 origin "$BASE"
    fi
    git checkout -q -f --detach "$BASE" && git clean -qfd -e build
    git -c user.name=llama-build -c user.email=llama-build@localhost am -q "$SERIES"/[0-9][0-9][0-9][0-9]-*.patch ||
        { git am --abort 2>/dev/null; die "$SERIES does not apply on ${BASE:0:12}: a newer series than this BASE pins"; }
    echo "applied $SERIES ($(ls "$SERIES"/[0-9][0-9][0-9][0-9]-*.patch | wc -l) patches)"
    echo "$want" >.lab-state
fi

echo "building (log: $SRC/build.log)"
# cmake auto-detects ccache on PATH; its default cache dir is outside this clone and can be
# read-only here (a confined run), so turn it off rather than depend on where it writes.
export CCACHE_DISABLE=1
if ! {
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=ON &&
        cmake --build build --target llama-bench llama-server test-backend-ops -j"$(nproc)"
} >build.log 2>&1; then
    grep -B2 -A12 -m1 -E 'CMake Error|error:' build.log || tail -n 25 build.log
    die "build failed; full log in $SRC/build.log"
fi
[[ -x build/bin/llama-server && -x build/bin/llama-bench ]] || die "build did not produce llama-server/llama-bench"
echo "built: $SRC/build/bin (llama-server, llama-bench, test-backend-ops)"
