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
# The series was read only as far as: what it touches (the asahi driver, nir, spirv, the
# Vulkan runtime, tests) and that its build files add sources only. Treat its results as
# unproven until the operator tests pass: mesa-side.sh run coopmat ./llama-sweep.sh test
#
#   mesa-side.sh deps                   only install the build packages (dnf)
#   mesa-side.sh build base|coopmat     install packages, fetch, build, install under
#                                       ~/src/mesa-side/<name>
#   mesa-side.sh check base|coopmat     what the driver reports
#   mesa-side.sh run base|coopmat CMD   run CMD with that driver; llama-bench.sh and
#                                       llama-sweep.sh add the name to their output file
#   mesa-side.sh remove                 delete ~/src/mesa-side (the packages stay)
#
# A faulting GPU program can take the desktop's rendering down with it until a reboot:
# save your work before the first run with the coopmat driver.

set -euo pipefail

REPO=https://github.com/omacom/mesa
BASE=7cda7850edd103ace21aac37d416d2fdf7a282e1
COOPMAT=795ae42a71c8889dd3b629d03a3aeb657501f20f
ROOT=${MESA_SIDE:-$HOME/src/mesa-side}
PKGS=(git-core meson ninja-build gcc gcc-c++ bison flex glslang python3-mako python3-pyyaml
    python3-packaging llvm-devel clang-devel libclc-devel spirv-llvm-translator-devel
    spirv-tools-devel libdrm-devel expat-devel elfutils-libelf-devel libzstd-devel zlib-devel
    vulkan-tools)

die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }

commit_of() {
    case $1 in
    base) echo "$BASE" ;;
    coopmat) echo "$COOPMAT" ;;
    *) die "name must be base or coopmat" ;;
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
    if [[ $(git rev-parse -q --verify HEAD 2>/dev/null) != "$sha" ]]; then
        echo "fetching Mesa at ${sha:0:12}"
        git fetch -q --depth 1 origin "$sha"
        git checkout -q --detach FETCH_HEAD
    fi
    echo "building the $name driver (log: $src/build.log)"
    # Only the Asahi Vulkan driver: no OpenGL, no window system, nothing else.
    if ! {
        { [[ -f build/build.ninja ]] || meson setup build --prefix="$ROOT/$name" -Dbuildtype=release \
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
    [[ $# -ge 3 ]] || die "usage: $0 run base|coopmat COMMAND [ARGUMENTS]"
    shift
    stage_run "$@"
    ;;
remove)
    rm -rf "$ROOT"
    echo "removed $ROOT"
    ;;
*)
    echo "usage: $0 {deps | build base|coopmat | check base|coopmat | run base|coopmat COMMAND... | remove}" >&2
    exit 2
    ;;
esac
