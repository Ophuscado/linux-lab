vulkan: Honeykrisp (Asahi Linux) on an M2 Ultra, measured against Metal on the same machine

Six patches on 2280f0f for llama.cpp's Vulkan backend on Apple GPUs under Mesa's Honeykrisp driver, from one Mac
Studio (M2 Ultra, 76 GPU cores, 192 GB). Every setting is off or unchanged unless its environment variable is set,
except 0002 and 0006, which only take paths that were taken before when the variable is unset or the pattern absent.

1. Matmul tile sizes and warptiles settable (`GGML_VK_MM_SIZES`, `GGML_VK_MMID_SIZES`, `GGML_VK_WT_S/M/L`).
   The medium tile at 256 threads, 128x64, gives prompts +12-23 % (Qwen3-Coder-Next Q8 pp2048 672 -> 780 t/s,
   Llama 2 7B Q4_0 pp512 620 -> 762, Gemma 4 Q4_K +16 %); every MUL_MAT and MUL_MAT_ID test passes.
2. The MUL_MAT_ID matrix-vector token limit settable (`GGML_VK_MMV_ID_MAX`); offset id views stay on the matmul
   path, which fixes an abort on `allow_misalign || misalign_bytes == 0` (955/955 MUL_MAT_ID pass).
3. Matrix-vector pipelines up to 16 columns (`GGML_VK_MMV_MAX_COLS`): a 9-token Qwen batch 37 -> 107 t/s, which is
   what a speculative step verifies; ngram-mod drafts on a code edit take Qwen from 30 to 55-59 t/s.
4. Rows per workgroup and the workgroup size settable (`GGML_VK_RM_STDQ`, `GGML_VK_RM_KQ`, `GGML_VK_DMMV_WG`).
5. q4_0 and q8_0 matrix-vector in ggml-metal's layout (`GGML_VK_MMV_SIMD=1`, mul_mat_vec_simd.comp): one
   4096x14336 step q4_0 81 -> 68 us, q8_0 160 -> 128 us; generation Llama 2 65.1 -> 69.7, Qwen 33.6 -> 34.8,
   GPT-OSS 20B 70.2 -> 70.9 t/s; 388/388 q4_0/q8_0 MUL_MAT and MUL_MAT_ID tests pass on the GPU.
6. RMS_NORM + SCALE fused (Metal fuses it too; 72 pairs a Qwen token). Correct, no measurable gain.

The same machine under macOS 15 (llama.cpp 2280f0f, tokens/s, pp512 / tg128):

| model | Metal | Vulkan through MoltenVK | Honeykrisp with this series |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 120.4 | 788 / 59.9 | 762 / 69.7 |
| GPT-OSS 20B | 1944 / 124.5 | 992 / 82.7 | 747 / 70.9 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 67.8 | 422 / 24.8 | 488 / 34.8 |

Where the remaining generation gap is, measured on this machine:

- Not fusion: a Qwen token is 1805 Vulkan launches against 1996 Metal dispatches (703 of them concurrent);
  ggml-vulkan fuses as much as ggml-metal, and its fusion is worth +40 % here (24.7 t/s with it off).
- The cost of a dependent launch: 4.0-4.2 us under Honeykrisp (with `HK_PERFTEST=designedusccdmbarrier`) against
  2.27 us on Metal; a Qwen token averages ~16 us a launch on Vulkan and ~7.4 on Metal.
- Memory: a grid-stride read reaches 610-655 GB/s from 64 MB to 1 GB under Honeykrisp; one vec4 per invocation
  only ~290 GB/s (65,536 workgroups for 256 MB); the f16 matrix-vector streams at 475 GB/s.

All raw data (Metal, MoltenVK, per-op timings, Metal's fusion ablation, the encoded graphs) and the scripts:
https://github.com/Ophuscado/linux-lab (results/macos, gpu/, KNOWLEDGE.md).
