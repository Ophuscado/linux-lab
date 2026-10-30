#!/usr/bin/env bash
# llama-run.sh [qwen | gemma | flash | gpt | gpt120 | MODEL.gguf]: llama.cpp's server on 127.0.0.1:8088 with the settings measured
# fastest and correct on this M2 Ultra (KNOWLEDGE.md, "GPU: llama.cpp on Vulkan against Metal"):
#   driver   mesa-side.sh's agxperf (coopmat + the Asahi compiler changes, bit 47 on local loads), clustering off:
#            prompts +17% over coopmat, generation the same or better, all 21303 operator tests pass; coopmat if
#            agxperf is not built, the system driver if neither is
#   barrier  HK_PERFTEST=designedusccdmbarrier: +7-9% generation, every test passes
#   matvec   the large workgroup; rows per workgroup 4 for Qwen, 2 for Gemma, 1 for GPT-OSS and dense models (cells
#            4252, 89035); q4_0 and q8_0 through the Metal-layout shader (src-patches/llama.cpp/honeykrisp 0005,
#            GGML_VK_MMV_SIMD=1): Llama 2 65.1 to 69.7 t/s, Qwen 33.6 to 34.8; a build without 0005 ignores it
#   batch    -ub/-b 8192: prompts 593 to 676 on Qwen
#   tiles    the medium matmul tile at 512 threads, 128x128 (honeykrisp 0001): prompts +12-23% at 256 threads 128x64
#            (Qwen 596 to 680, Gemma 770 to 905 at pp2048), 512 threads 128x128 +2-4% more at this -ub 8192; its
#            matrices 16x16x16, not the driver's first shape 8x8x8: Llama 2 +18%, the MoE models +1-10%; the
#            experts' matmuls in a 128x32 small tile up to 64 tokens each (0011): short prompts up to +22%
#            experts on the matrix-vector path past 8 tokens only at 2 tokens an expert or fewer (0013):
#            Gemma 64-token batches +34%, GPT-OSS 20B +61%
#   cores    GGML_VK_SHADER_CORES=152 (0007): Honeykrisp reports no core count; long contexts 2.5-4.6x
#   experts  MoE layers on the matrix-vector path up to 64 tokens, not 8 (src-patches/llama.cpp/honeykrisp): batches
#            of 9-64 tokens +12-42% on Qwen; dense layers on it up to 16 tokens, not 8
#            (src-patches/llama.cpp/honeykrisp): 9-16 token batches 2-4x (Qwen 9 tokens 37 to 107 t/s)
#   drafts   ngram-mod speculation (Qwen code edit: none 30, default 64-token drafts 46-49, 128-token 55 t/s); Gemma 4 with its MTP head as well (+74%); Flash-Next
#            with its MTP head alone (+40%). MTP answers can differ from plain decoding (batched verification)
# LLAMA_CLUSTER=1 turns clustering on (against off: prompts +4-14%, generation -4 to -10%), for prompt-heavy work.
# Arguments after the model go to llama-server as they are.
set -euo pipefail

LAB=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
# The first that exists: the lab's tree (src/, build/, git-ignored) or where they were before 27 Oct (~/src).
first() { local p; for p in "$@"; do [[ -e $p ]] && { echo "$p"; return; }; done; echo "$1"; }
# The patch series build (src-patches/llama.cpp/honeykrisp, every setting below and every measured number) first;
# src/llama.cpp/build-run is the older tree with the tile patch alone.
SERVER=$(first "$LAB/src/llama.cpp-simd/build/bin/llama-server" "$LAB/src/llama.cpp/build-run/bin/llama-server" "$HOME/src/llama.cpp-tune-prod/build-run/bin/llama-server")
LLM=$HOME/Projects/_llm
SIDE=${MESA_SIDE:-$(first "$LAB/build/mesa-side" "$HOME/src/mesa-side")}
MCP=$(first "$LAB/config/mcp.json" "$HOME/src/mcp.json")
CACHE=$(first "${XDG_CACHE_HOME:-$HOME/.cache}/llama-run" "$HOME/src/cache")  # slot saves: a cache, not backed up
mkdir -p "$CACHE"

model=${1:-qwen}; [[ $# -gt 0 ]] && shift
draft=() rows=2
case $model in
qwen) M=$LLM/Qwen3-Coder-Next/UD-Q8_K_XL/model.gguf  # drafts up to 128: +13% over the default 64
    rows=4 draft=(--spec-type ngram-mod --spec-ngram-mod-n-max 128 --spec-ngram-mod-n-min 96) ;;
gemma) M=$LLM/Gemma-4-26B-A4B-Instruct/UD-Q4_K_XL/model.gguf
    draft=(--spec-type draft-mtp,ngram-mod -md "$LLM/Gemma-4-26B-A4B-Instruct/mtp-Q8_0.gguf" -ngld 99) ;;
flash) M=$LLM/Qwen3.8-Flash-Next/UD-Q4_K_XL/model.gguf  # MTP alone beats MTP with ngram-mod here
    draft=(--spec-type draft-mtp -md "$LLM/Qwen3.8-Flash-Next/mtp-Q4_K_M.gguf" -ngld 99) ;;
gpt) M=$LLM/GPT-OSS-20B/UD-Q8_K_XL/model.gguf; rows=1; draft=(--spec-type ngram-mod) ;;
gpt120) M=$LLM/GPT-OSS-120B/UD-Q4_K_XL/model.gguf; rows=1; draft=(--spec-type ngram-mod) ;;
*) M=$model; rows=1; draft=(--spec-type ngram-mod) ;;
esac
[[ -f $M ]] || { echo "no model file: $M" >&2; exit 1; }

for d in agxperf coopmat; do
    icd=$(compgen -G "$SIDE/$d/share/vulkan/icd.d/asahi_icd.*.json" | head -n 1 || true)
    [[ -n $icd ]] && { export VK_DRIVER_FILES=$icd; echo "driver: $d"; break; }
done
[[ -n ${VK_DRIVER_FILES:-} ]] || echo "driver: the system's (no mesa-side driver built)"
[[ ${LLAMA_CLUSTER:-0} == 1 ]] || export AGX_CLUSTER_OFF=1
export GGML_VK_WT_M=512,128,128,,32,32,,16,16,16 GGML_VK_MMV_ID_MAX=64 GGML_VK_MMV_ID_PER_EXPERT=2 GGML_VK_MMV_MAX_COLS=16 HK_PERFTEST=designedusccdmbarrier GGML_VK_DMMV_WG=large GGML_VK_MMV_SIMD=1 GGML_VK_RM_STDQ=$rows GGML_VK_RM_KQ=$rows \
    GGML_VK_SHADER_CORES=${GGML_VK_SHADER_CORES:-152} \
    GGML_VK_MMID_SIZES=sm GGML_VK_WT_S=256,128,32,,32,16 GGML_VK_MMID_S_MAX=64  # experts: 128x32 up to 64 tokens each (0011)

exec "$SERVER" -m "$M" "${draft[@]}" \
    -ngl all -t 16 -fa on -np 1 -ub 8192 -b 8192 \
    -ctk q8_0 -ctv q8_0 --kv-unified --swa-full \
    --mcp-servers-config "$MCP" --tools all \
    -cram 102400 --cache-prompt --cache-idle-slots --slot-save-path "$CACHE" \
    --sleep-idle-seconds 180 --host 127.0.0.1 --port 8088 "$@"
