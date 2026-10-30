#!/usr/bin/env bash
# llama-compare.sh [NAME...]: on Linux, the same llama.cpp tests macos/collect.sh's llama step ran with Metal, so the two
# sit side by side: llama-bench pp512/pp2048/tg128, the 1-512 token batch curve, generation after 0-16k tokens of
# context (depth), speculative decoding on the code edit of macos/spec-req.py (none, ngram-mod 64 and 128, the MTP
# head where the model has one), and test-backend-ops perf of FLASH_ATTN_EXT (once). Models and names from
# macos/models.txt (default: all present); the settings of gpu/llama-run.sh. Output: var/compare-<time>/, JSON as on
# macOS. Takes the GPU lock.
#
# Environment: STEPS (default "bench batches depth spec ops"), LLAMA_BIN (a build/bin with llama-bench and llama-server; default src/llama.cpp-simd/build/bin, the
# honeykrisp series), LLM (models, default ~/Projects/_llm).
set -euo pipefail
LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
B=${LLAMA_BIN:-$LAB/src/llama.cpp-simd/build/bin}
LLM=${LLM:-$HOME/Projects/_llm}
OUT=$LAB/var/compare-$(date +%Y%m%d-%H%M%S)
die() { printf '\nERR: %s\n' "$*" >&2; exit 1; }
[[ -x $B/llama-bench && -x $B/llama-server ]] || die "no llama-bench and llama-server in $B"
mkdir -p "$OUT"

for d in agxperf coopmat; do
    icd=$(compgen -G "$LAB/build/mesa-side/$d/share/vulkan/icd.d/asahi_icd.*.json" | head -n 1 || true)
    [[ -n $icd ]] && { export VK_DRIVER_FILES=$icd; echo "driver: $d" | tee "$OUT/driver.txt"; break; }
done
export AGX_CLUSTER_OFF=1 HK_PERFTEST=designedusccdmbarrier GGML_VK_DMMV_WG=large GGML_VK_MMV_SIMD=1
export GGML_VK_WT_M=256,128,64,,32,32 GGML_VK_MMV_ID_MAX=64 GGML_VK_MMV_MAX_COLS=16 GGML_VK_SHADER_CORES=${GGML_VK_SHADER_CORES:-152}
# Rows per workgroup as llama-run.sh sets them; ROWS=N for every model instead.
rows() { [[ -n ${ROWS:-} ]] && { echo "$ROWS"; return; }; case $1 in qwen) echo 4 ;; gemma) echo 2 ;; *) echo 1 ;; esac; }

STEPS=" ${STEPS:-bench batches depth spec ops} "
on() { [[ $STEPS == *" $1 "* ]]; }
exec 9>"$HOME/.cache/linux-lab-gpu.lock"; flock 9
if on ops; then
    "$B/test-backend-ops" perf -b Vulkan0 -o FLASH_ATTN_EXT >"$OUT/ops-FLASH_ATTN_EXT.txt" 2>&1 || echo "ops: test-backend-ops failed" >>"$OUT/errors.txt"
fi
want=" $* "
while IFS='|' read -r name file mtp; do
    [[ -z $name || $name == \#* ]] && continue
    [[ $# == 0 || $want == *" $name "* ]] || continue
    f=$LLM/$file; [[ -f $f ]] || { echo "$name: no $f, skipped"; continue; }
    mf=; [[ -n $mtp && -f $LLM/$mtp ]] && mf=$LLM/$mtp
    r=$(rows "$name"); export GGML_VK_RM_STDQ=$r GGML_VK_RM_KQ=$r
    echo "== $name (rows $GGML_VK_RM_STDQ)"
    on bench && "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 512,2048 -n 128 -r 3 -o json >"$OUT/llama-$name-bench.json" 2>>"$OUT/errors.txt"
    on batches && "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 8192 -b 8192 -p 1,2,4,8,9,12,16,24,32,48,64,128,512 -n 0 -r 2 -o json \
        >"$OUT/llama-$name-batches.json" 2>>"$OUT/errors.txt"
    on depth && "$B/llama-bench" -m "$f" -ngl 99 -fa 1 -ub 2048 -p 0 -n 32 -d 0,1024,4096,16384 -r 2 -o json \
        >"$OUT/llama-$name-depth.json" 2>>"$OUT/errors.txt"
    on spec || continue
    for c in "none|" "ngram-mod-64|--spec-type ngram-mod" \
        "ngram-mod-128|--spec-type ngram-mod --spec-ngram-mod-n-max 128 --spec-ngram-mod-n-min 96" \
        ${mf:+"mtp|--spec-type draft-mtp -md $mf -ngld 99"}; do
        # shellcheck disable=SC2086
        "$B/llama-server" -m "$f" ${c#*|} -ngl all -fa on -np 1 -c 16384 -ub 8192 -b 8192 -ctk q8_0 -ctv q8_0 \
            --host 127.0.0.1 --port 8099 >"$OUT/server.log" 2>&1 &
        s=$!
        for ((i = 0; i < 600; i++)); do curl -sf http://127.0.0.1:8099/health >/dev/null && break; sleep 1; done
        echo "$name ${c%%|*}: $(python3 -I "$LAB/macos/spec-req.py" 8099 "$LAB/gpu/llama-run.sh" 2>&1 | tail -n 1)" | tee -a "$OUT/llama-spec.txt"
        kill "$s"; wait "$s" 2>/dev/null || true
    done
done <"$LAB/macos/models.txt"
echo "saved: $OUT"
