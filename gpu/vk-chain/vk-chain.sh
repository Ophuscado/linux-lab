#!/bin/bash
# vk-chain.sh build | run [COUNT] [ELEMENTS]: build vk-chain (needs glslc or glslangValidator and
#   metal-chain.m: the same measurements on Metal, for macOS on the same Mac (see its header).
# vulkan-loader-devel), then time one launch alone and in a dependent chain on each Mesa that
# mesa-side.sh built and under each Honeykrisp barrier variant. A token of an LLM is ~1500
# dependent launches: chain us x 1500 is the floor of its generation time.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); SIDE=${MESA_SIDE:-$HERE/../../build/mesa-side}
[[ -n ${MESA_SIDE:-} || -d $SIDE || ! -d $HOME/src/mesa-side ]] || SIDE=$HOME/src/mesa-side
case ${1:-run} in
build)
    for sh in add reduce chase fat dot addk q8dot read read8 read4 readrow; do
        if command -v glslc >/dev/null; then glslc -O --target-env=vulkan1.2 "$HERE/$sh.comp" -o "$HERE/$sh.spv"
        else glslangValidator -V --target-env vulkan1.2 "$HERE/$sh.comp" -o "$HERE/$sh.spv" | grep -v "^/\?.*\.comp$" || true; [[ -s $HERE/$sh.spv ]] || { echo "$sh.comp did not compile" >&2; exit 1; }; fi
    done
    # mma.comp needs VK_KHR_cooperative_matrix (Honeykrisp with the coopmat series; not MoltenVK).
    for nn in 8 16; do
        if command -v glslc >/dev/null; then glslc -O --target-env=vulkan1.3 -DN=$nn "$HERE/mma.comp" -o "$HERE/mma$nn.spv" || true
        else glslangValidator -V --target-env vulkan1.3 -DN=$nn "$HERE/mma.comp" -o "$HERE/mma$nn.spv" | grep -v "^/\?.*\.comp$" || true; fi
    done
    if [[ $(uname) == Darwin ]]; then
        # macOS: Homebrew's loader and headers, MoltenVK as the driver (vulkan step of macos/collect.sh).
        hb=$(brew --prefix); cc -O2 -I"$hb/include" -o "$HERE/vk-chain" "$HERE/vk-chain.c" -L"$hb/lib" -lvulkan -Wl,-rpath,"$hb/lib"
        echo "built $HERE/vk-chain"
    else
        cc -O2 -o "$HERE/vk-chain" "$HERE/vk-chain.c" -lvulkan && echo "built $HERE/vk-chain"
    fi ;;
run)
    [[ -x $HERE/vk-chain ]] || "$0" build
    for icd in ${VKCHAIN_ICDS:-system} "$SIDE"/*/share/vulkan/icd.d/asahi_icd.*.json; do
        [[ $icd == system || -f $icd ]] || continue
        name=system; e=(); [[ $icd == system ]] || { name=${icd#"$SIDE"/}; name=${name%%/*}; e=(VK_DRIVER_FILES="$icd"); }
        for v in default designedusccdmbarrier trackcdmbarrier; do
            pv=(); [[ $v == default ]] || pv=(HK_PERFTEST="$v")
            env ${e[@]+"${e[@]}"} ${pv[@]+"${pv[@]}"} "$HERE/vk-chain" "${2:-1500}" "${3:-4096}" 20 2>&1 | grep -v '^device' | sed "s|^|$name $v: |" || true
        done
    done ;;
barriers)
    # barriers [ICD]: one Mesa, the cost of workgroup barriers and of subgroup adds inside a shader
    # (16 rounds of a 256-thread row sum per launch), against the plain add shader.
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for t in "add 0 0" "reduce 0 1" "reduce 0 16" "reduce 1 1" "reduce 1 16"; do
        set -- $t; env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 1500 65536 10 "$1" "$2" "$3" | grep -v '^device' | sed "s|^|$1 mode $2 iters $3: |"
    done ;;
mma)
    # mma [ICD]: the matrix hardware with no global memory (mma.comp): TFLOPS of NxNxN f16 multiply-adds, from
    # registers (mode 0), with A and B loaded from shared memory each step, B column-major as llama.cpp's
    # (mode 1) or row-major (mode 2), mode 1 with a barrier every 2 steps (3) or llama.cpp's padded rows (4);
    # 1216 workgroups of 8 subgroups, 1024 steps of 4 ops each.
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for nn in 8 16; do for m in 0 1 2 3 4; do
        env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=1216 "$HERE/vk-chain" 20 65536 5 mma$nn $m 1024 2>&1 |
            awk -v n=$nn -v m=$m '/^free/ { printf "%dx%dx%d mode %d: %.1f TFLOPS (%.1f us a launch)\n", n, n, n, m, 1216 * 8 * 1024 * 4 * 2 * n * n * n / ($2 * 1e6), $2 } /error|not|lost/'
    done; done ;;
latency)
    # latency [ICD]: one GPU load's latency, from 1000 dependent loads per launch, in buffers
    # from 16 KB (caches) to 256 MB (DRAM), against an empty launch (ITERS 0).
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for n in 4096 262144 4194304 67108864; do for it in 0 1000; do
        env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 20 "$n" 5 chase 0 "$it" | grep '^chain' | sed "s|^|$((n * 4 / 1024)) KB, $it loads: |"
    done; done ;;
clock)
    # clock [ICD]: one thread's dependent multiply-adds (100k per launch): ns per step, cold and
    # while the GPU is kept busy by a free-running add load (does the clock ramp up under load?).
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    t() { env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 5 256 5 chase 1 100000 | awk '/^chain/ { printf "%s: %.2f ns per multiply-add\n", L, $2 * 1000 / 100000 }' L="$1"; }
    t "idle GPU"
    env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 1500 4194304 400 add >/dev/null 2>&1 & bg=$!; sleep 2
    t "GPU busy"; kill $bg 2>/dev/null; wait $bg 2>/dev/null
    t "idle again"
    # The loop's own cost out: 16 multiply-adds per step against 1 per step.
    a=$(env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 5 256 5 chase 1 100000 | awk '/^chain/ { print $2 }')
    b=$(env ${e[@]+"${e[@]}"} "$HERE/vk-chain" 5 256 5 chase 2 100000 | awk '/^chain/ { print $2 }')
    awk -v a="$a" -v b="$b" 'BEGIN { ns = (b - a) * 1000 / (100000 * 15); printf "one dependent multiply-add: %.2f ns (loop step alone %.2f ns); at 1398 MHz that is %.1f cycles\n", ns, a / 100 - ns, ns * 1.398 }' ;;
switch)
    # switch [ICD]: a chained launch with the same pipeline, alternating two pipelines, rebinding
    # the descriptor set and constants each time, and both (ggml switches pipeline at every op).
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for ar in "0 0" "1 0" "0 1" "1 1"; do set -- $ar
        env ${e[@]+"${e[@]}"} VKCHAIN_ALT=$1 VKCHAIN_REBIND=$2 "$HERE/vk-chain" 1500 4096 20 | grep -v '^device' | sed "s|^|alternate $1, rebind $2: |"
    done
    # ggml's binary-op shape: three buffers, 30 words of constants, divisions per element (mode 0) or not (1).
    for m in 0 1; do env ${e[@]+"${e[@]}"} VKCHAIN_ALT=1 VKCHAIN_REBIND=1 "$HERE/vk-chain" 1500 4096 20 fat $m 0 | grep -v '^device' | sed "s|^|ggml-shaped add, divisions $((1 - m)): |"; done ;;
dot)
    # dot [ICD]: the simplest matrix-vector (f32, 2 rows per 128-thread workgroup) at ggml's small shapes
    # and a large one, with the vector shared by all workgroups (as ggml) or one per workgroup.
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for mk in "512 2048" "2048 512" "4096 4096"; do set -- $mk
        for mode in 0 1 2 3; do
            env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=$(($1 / 2)) "$HERE/vk-chain" 1500 $((($1 + 2) * $2)) 10 dot $mode $2 | grep -v '^device' |
                sed "s|^|$1x$2 f32, vector $( ((mode % 2 == 0)) && echo shared || echo private), loads $( ((mode >= 2)) && echo 'batched by 8' || echo 'one at a time'): |"
        done
    done
    # The same shapes in q8_0, ggml's layout, lean: rows x (k/32 blocks of 17 words) + the f32 vector + outputs.
    for mk in "512 2048" "2048 512" "4096 4096" "4096 14336"; do set -- $mk
        words=$(( $1 * ($2 / 32) * 17 + 2 * $2 + 64 + 2 * $1 + 2 ))
        env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=$(($1 / 2)) "$HERE/vk-chain" 1500 $(( (words + 1) / 2 )) 10 q8dot 0 $2 | grep -v '^device' | sed "s|^|$1x$2 q8_0 lean: |"
    done ;;
masks)
    # masks ICD MASK...: the chained launch (add, 4096 and 1M floats; dot 512x2048) under each
    # HK_CDM_BARRIER_MASK (coopmat Mesa's exact CDM barrier word; 0xfffff is G14's default,
    # 0x17f the G13X designed set). A mask that hangs the GPU times out after 5 s and the next one runs.
    [[ -x $HERE/vk-chain ]] || "$0" build
    icd=$2; shift 2
    for m in "$@"; do
        a=$(VK_DRIVER_FILES=$icd HK_CDM_BARRIER_MASK=$m "$HERE/vk-chain" 1500 4096 10 | awk '/^chain/ { print $2 }')
        b=$(VK_DRIVER_FILES=$icd HK_CDM_BARRIER_MASK=$m "$HERE/vk-chain" 1500 262144 10 | awk '/^chain/ { print $2 }')
        c=$(VK_DRIVER_FILES=$icd HK_CDM_BARRIER_MASK=$m VKCHAIN_GROUPS=256 "$HERE/vk-chain" 1500 $((514 * 2048)) 10 dot 0 2048 | awk '/^chain/ { print $2 }')
        printf '%-8s add 16 KB %6s us   add 1 MB %6s us   dot 512x2048 %6s us\n' "$m" "${a:-HUNG}" "${b:-HUNG}" "${c:-HUNG}"
    done ;;
groups)
    # groups [ICD]: one chained add of 1 MB and of 16 MB over 8 to 4096 workgroups of 256 threads.
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    for n in 262144 4194304; do for g in 8 32 76 152 304 608 1024 4096; do
        env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=$g "$HERE/vk-chain" 1500 $n 10 addk | awk -v g=$g -v n=$n '/^(free|chain)/ { printf "%5d KB, %4d workgroups: %-5s %7.2f us\n", n * 4 / 1024, g, $1, $2 }'
    done; done ;;
bw)
    # bw [ICD]: read bandwidth, GB/s, from 1 MB (caches) to 1 GB (memory), in back-to-back launches with no barrier, at
    # one vec4 per invocation and with 1216 workgroups walking the buffer (16 per GPU core); then the 256 MB case on every
    # memory type the buffer may use. Plain f16 matrix-vector work streamed at 475 GB/s here and 820 on Metal (29 Oct).
    [[ -x $HERE/vk-chain ]] || "$0" build
    e=(); [[ -z ${2:-} ]] || e=(VK_DRIVER_FILES="$2")
    gbs() { awk -v n="$1" '/^free/ { printf "%8.1f GB/s (%.1f us)", n * 4 / ($2 * 1000), $2 }'; }
    for mb in 1 16 64 256 1024; do
        n=$((mb * 262144)) c=$(( mb >= 256 ? 20 : 200 ))
        a=$(env ${e[@]+"${e[@]}"} "$HERE/vk-chain" $c $n 5 read | gbs $n)
        b=$(env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=1216 "$HERE/vk-chain" $c $n 5 read | gbs $n)
        c8=$(env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=1216 "$HERE/vk-chain" $c $n 5 read8 | gbs $n)
        c4=$(env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=1216 "$HERE/vk-chain" $c $n 5 read4 | gbs $n)
        printf '%5d MB: one vec4 each %s   1216 groups %s   8-byte loads %s   4-byte loads %s\n' "$mb" "$a" "$b" "$c8" "$c4"
    done
    # The matrix-vector's pattern: each group reads its own contiguous slice (as its rows), 117 MB as an f16
    # 4096x14336, over as many groups as the matrix-vector launches (rows / 2) and fewer.
    for g in 2048 1024 512 1216 256; do
        r=$(env ${e[@]+"${e[@]}"} VKCHAIN_GROUPS=$g "$HERE/vk-chain" 20 29360128 5 readrow | gbs 29360128)
        printf '117 MB, %4d groups each on its own slice: %s\n' "$g" "$r"
    done
    env ${e[@]+"${e[@]}"} VKCHAIN_MEMTYPES=1 "$HERE/vk-chain" 1 1024 1 read | grep '^memory type' | while read -r _ _ k _; do
        k=${k%:}; r=$(env ${e[@]+"${e[@]}"} VKCHAIN_MEMTYPE=$k "$HERE/vk-chain" 20 67108864 5 read 2>&1 | gbs 67108864)
        printf '256 MB on memory type %s: %s\n' "$k" "${r:-not usable}"
    done ;;
*) echo "usage: $0 build | run [COUNT] [ELEMENTS] | barriers [ICD] | latency [ICD] | clock [ICD] | switch [ICD] | dot [ICD] | masks ICD MASK... | groups [ICD] | bw [ICD]" >&2; exit 2 ;;
esac
