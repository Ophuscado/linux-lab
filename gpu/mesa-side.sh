#!/usr/bin/env bash
# mesa-side.sh: build another Mesa Vulkan driver for the Apple GPU beside the system one
# and run single programs with it. The system Mesa is never touched: a program uses the
# side driver only when started through "mesa-side.sh run", which points the Vulkan loader
# at it with VK_DRIVER_FILES.
#
# Two drivers can be built, both from https://github.com/omacom/mesa at fixed commits:
#   base     upstream Mesa main where the series below starts (26.3 development). Shows
#            what newer Mesa alone changes against the system's 26.2
#   coopmat  that plus a third-party series (pull requests 3 to 6, 56 commits by one
#            author, not submitted to Mesa) that adds VK_KHR_cooperative_matrix using
#            matrix instructions of the GPU, and changes how compute work is batched.
#            llama.cpp uses cooperative matrices for prompt processing when a driver
#            offers them. On the M2 Max and Ultra GPU the series enables them by default
#            (AGX_SIMDMAT=0 switches them off)
#   agxperf  coopmat plus three Asahi compiler changes from another author's branch, posted in
#            llama.cpp issue 10982 with pp512 +42% on a 7B model (not submitted to Mesa either):
#            a post-RA instruction scheduler for parallelism, bit 47 on local-memory loads and
#            stores, and more headroom in the pressure scheduler so local loads cluster
#            (src-patches/mesa/agxperf: his three commits rebased onto the coopmat commit, and ours, the AGX_BIT47 switch)
#            AGX_BIT47 (0 off, 1 loads and stores, 2 loads, 3 stores) chooses where bit 47 is set
#   agxilp   agxperf without bit 47, which breaks ARGMAX on the M2 Ultra (src-patches/mesa/agxilp: his first two commits);
#            AGX_NO_ILP_SCHED=1 and AGX_CLUSTER_OFF=1 switch its two changes off at run time
#   next     the series as its pull request stands on 25 Oct (9323171c), newer than coopmat's 795ae42a71
#   nextperf next with the agxperf compiler changes (if the patch still applies)
# The series was read only as far as: what it touches (the asahi driver, nir, spirv, the
# Vulkan runtime, tests) and that its build files add sources only. Treat its results as
# unproven until the operator tests pass: mesa-side.sh run coopmat ./llama-sweep.sh test
#
#   mesa-side.sh deps                   only install the build packages (dnf)
#   mesa-side.sh build base|coopmat|agxperf  install packages, fetch, build, install under
#                                       build/mesa-side/<name>
#   mesa-side.sh check base|coopmat     what the driver reports
#   mesa-side.sh run base|coopmat CMD   run CMD with that driver; llama-bench.sh and
#                                       llama-sweep.sh add the name to their output file
#   mesa-side.sh remove                 delete build/mesa-side (the packages stay)
#
# A faulting GPU program can take the desktop's rendering down with it until a reboot:
# save your work before the first run with the coopmat driver.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LAB=$(cd "$HERE/.." && pwd)
REPO=https://github.com/omacom/mesa
BASE=7cda7850edd103ace21aac37d416d2fdf7a282e1
COOPMAT=795ae42a71c8889dd3b629d03a3aeb657501f20f
# The series' head of 25 Oct 2026 (pull request 6 again, 9323171c: compute batching across barriers, a revert
# of the full CDM barrier after graphics, shared-memory address fixes); nextperf adds the agxperf changes.
NEXT=9323171c12c5aa6055f1031ea26c16c247191987
# Drivers live in the lab's build/mesa-side (git-ignored); ~/src/mesa-side, where they were built before
# 27 Oct, is used while it exists and the lab's does not.
ROOT=${MESA_SIDE:-}
if [[ -z $ROOT ]]; then ROOT=$LAB/build/mesa-side; [[ ! -d $ROOT && -d $HOME/src/mesa-side ]] && ROOT=$HOME/src/mesa-side; fi
PKGS=(git-core meson ninja-build gcc gcc-c++ bison flex glslang python3-mako python3-pyyaml
    python3-packaging llvm-devel clang-devel libclc-devel spirv-llvm-translator-devel
    spirv-tools-devel libdrm-devel expat-devel elfutils-libelf-devel libzstd-devel zlib-devel
    vulkan-tools)

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

commit_of() {
    case $1 in
    base) echo "$BASE" ;;
    coopmat | agxperf | agxilp) echo "$COOPMAT" ;;
    next | nextperf) echo "$NEXT" ;;
    *) die "name must be base, coopmat, agxperf, agxilp, next or nextperf" ;;
    esac
}

icd_of() {
    local f
    f=$(compgen -G "$ROOT/$1/share/vulkan/icd.d/asahi_icd.*.json" | head -n 1) || true
    [[ -n $1 && -n $f ]] || die "no $1 driver under $ROOT; run: $0 build $1"
    echo "$f"
}

stage_deps() {
    local missing=() pkg
    for pkg in "${PKGS[@]}"; do
        rpm -q --quiet --whatprovides "$pkg" || missing+=("$pkg")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        sudo dnf install -y "${missing[@]}" ||
            die "dnf could not install the build packages; 'sudo dnf builddep mesa' installs a superset"
    fi
}

stage_build() {
    local name=$1 sha src
    sha=$(commit_of "$name")
    src=$ROOT/src-$name
    stage_deps
    mkdir -p "$ROOT"
    if [[ ! -d $src/.git ]]; then
        git init -q "$src"
        git -C "$src" remote add origin "$REPO"
    fi
    cd "$src"
    # agxperf, nextperf and agxilp: a series of src-patches/mesa (xingjianll's commits, ours after them) applied
    # with git am on the pinned commit. .lab-state names what the tree holds, so a changed series is applied again.
    local series="" want
    case $name in agxperf | nextperf) series=agxperf ;; agxilp) series=agxilp ;; esac
    want=$sha
    [[ -z $series ]] || want="$sha $(cat "$LAB/src-patches/mesa/$series"/[0-9][0-9][0-9][0-9]-*.patch | sha256sum | cut -c1-16)"
    if [[ $(cat .lab-state 2>/dev/null) != "$want" ]]; then
        if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
            echo "fetching Mesa at ${sha:0:12}"
            git fetch -q --depth 1 origin "$sha"
        fi
        git checkout -q -f --detach "$sha" && git clean -qfd -- src   # the build dir stays
        if [[ -n $series ]]; then
            git -c user.name=mesa-side -c user.email=mesa-side@localhost am -q "$LAB/src-patches/mesa/$series"/[0-9][0-9][0-9][0-9]-*.patch ||
                { git am --abort 2>/dev/null; die "src-patches/mesa/$series does not apply on ${sha:0:12}"; }
            echo "applied src-patches/mesa/$series ($(ls "$LAB/src-patches/mesa/$series"/[0-9][0-9][0-9][0-9]-*.patch | wc -l) commits)"
        fi
        echo "$want" >.lab-state
    fi
    echo "building the $name driver (log: $src/build.log)"
    # Only the Asahi Vulkan driver: no OpenGL, no window system, nothing else.
    if ! {
        # The system's Python (with packaging, PKGS): a virtualenv first in PATH has no packaging module, and
        # meson's configure then fails. A configure that failed before leaves build/ without build.ninja: wiped.
        export PATH="/usr/bin:$PATH"
        { [[ -f build/build.ninja ]] || meson setup build $([[ -d build ]] && echo --wipe) --prefix="$ROOT/$name" -Dbuildtype=release \
            -Dgallium-drivers= -Dvulkan-drivers=asahi -Dplatforms= -Dglx=disabled -Degl=disabled \
            -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dllvm=enabled \
            -Dvideo-codecs= -Dbuild-tests=false -Dtools=; } &&
            ninja -C build install
    } >build.log 2>&1; then
        grep -B2 -A12 -m1 -E 'ERROR|error:' build.log || tail -n 25 build.log
        die "build failed; full log in $src/build.log"
    fi
    echo "installed: $(icd_of "$name")"
    stage_check "$name"
}

stage_check() {
    local icd
    icd=$(icd_of "$1")
    VK_DRIVER_FILES=$icd vulkaninfo --summary 2>&1 | grep -E 'deviceName|driverName|driverInfo|apiVersion' ||
        die "the $1 driver does not load; see: VK_DRIVER_FILES=$icd vulkaninfo --summary"
    printf 'cooperative matrices: '
    if VK_DRIVER_FILES=$icd vulkaninfo 2>/dev/null | grep -q 'VK_KHR_cooperative_matrix'; then echo offered; else echo "not offered"; fi
}

stage_run() {
    local name=$1 icd
    shift
    icd=$(icd_of "$name")
    VK_DRIVER_FILES=$icd BENCH_LABEL=mesa-$name exec "$@"
}

case ${1:-} in
deps) stage_deps ;;
build) stage_build "${2:-}" ;;
check) stage_check "${2:-}" ;;
run)
    [[ $# -ge 3 ]] || die "usage: $0 run NAME COMMAND [ARGUMENTS]"
    shift
    stage_run "$@"
    ;;
remove)
    rm -rf "$ROOT"
    echo "removed $ROOT"
    ;;
*)
    echo "usage: $0 {deps | build NAME | check NAME | run NAME COMMAND... | remove}, NAME base, coopmat, agxperf or agxilp" >&2
    exit 2
    ;;
esac
