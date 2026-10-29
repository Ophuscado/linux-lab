Follow-up for issue 10982: Honeykrisp against Metal on the same M2 Ultra

Hi again! Since my last comment I booted macOS on the same Mac Studio (M2 Ultra, 76 GPU cores, 192 GB) and ran the same llama.cpp commit (2280f0f) with Metal, and with the Vulkan backend through MoltenVK. That gives a direct comparison on identical hardware, so I'm sharing the numbers in case they help.

**Tokens per second, prompt (pp512 / pp2048) / generation (tg128)**

| Model | Metal (macOS) | Vulkan via MoltenVK (macOS) | Vulkan via Honeykrisp (Linux) |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 1538 / 120.4 | 788 / 836 / 59.9 | 762 / 803 / 68.7 |
| GPT-OSS 20B Q8_0 | 1944 / 2146 / 124.5 | 992 / 1221 / 82.7 | 819 / 1160 / 71.6 |
| GPT-OSS 120B Q4_K | 1001 / 1300 / 94.2 | - | 390 / 656 / 50.1 |
| Gemma 4 26B-A4B Q4_K | 2100 / 2338 / 95.2 | - | 709 / 907 / 39.9 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 1817 / 67.8 | 422 / 574 / 24.8 | 449 / 681 / 34.2 |

Same tests and flags on both systems (llama-bench, flash attention on, all layers on the GPU, the mean of 2-5 runs). macOS 15.8.1 for the first two columns. On Linux, the patches below and Honeykrisp built from Mesa's development tree with a third-party cooperative-matrix and compiler series, with `HK_PERFTEST=designedusccdmbarrier`. The batch curve (1-512 tokens) and speculative decoding for every model, on both systems, are in the links at the end.

**What I take from it**

- Vulkan on macOS is no faster than Vulkan on Linux, so most of the gap to Metal is in the Vulkan backend's shaders and graph on this GPU, not in Mesa or the kernel.
- It isn't fusion: a Qwen token is 1805 Vulkan launches against 1996 Metal dispatches, and the Vulkan backend already fuses as much as Metal does. Turning fusion off drops Qwen to 24.7 t/s, so it's worth +40 % here.
- It's the cost of each dependent launch: about 4 us under Honeykrisp against 2.3 us on Metal (a microbenchmark that chains small dispatches). Averaged over a Qwen token it is ~16 us per launch on Vulkan and ~7.4 us on Metal, where about a third of the dispatches also run concurrently.
- Speculative verification and long contexts widen it: from about 2x at one token, Metal is 4-5x ahead at 64-token batches, and with a ~4,000-token prompt Llama 2 generates 24.7 t/s on Linux (36 % of its short-prompt rate) against 90 on Metal (75 %).
- Memory isn't the limit: a simple read shader gets 610-655 GB/s under Honeykrisp, but only ~290 GB/s when the grid has one workgroup per small slice, so many-small-workgroup shaders pay for launching them.

**Changes I tried on Linux** (a small patch series, all opt-in through environment variables)

- Medium matmul tile at 256 threads, 128x64: prompts +12-23 % (Qwen pp2048 672 to 780 t/s).
- The matrix-vector path for batches of 9-64 tokens instead of stopping at 8: a 9-token Qwen batch goes from 37 to 107 t/s, which is what makes speculative decoding pay (a code edit with ngram-mod drafts: 30 to 55-59 t/s).
- A q4_0/q8_0 matrix-vector shader laid out like Metal's kernel_mul_mv: one 4096x14336 step 81 to 68 us (q4_0) and 160 to 128 us (q8_0); generation +7 % on Llama 2, +2-4 % on Qwen. All MUL_MAT and MUL_MAT_ID tests pass.

Two of these look worth proposing on their own, and I'm happy to open pull requests if that's welcome: a fix for an abort in MUL_MAT_ID with offset expert-id views, and the 256-thread tile as Honeykrisp's default.

Everything is public, with the raw data and the scripts:

- The numbers above and how they were measured: https://github.com/Ophuscado/linux-lab/blob/master/KNOWLEDGE.md#gpu-llamacpp-on-vulkan-against-metal
- Every result on both systems (the 1-512 batch curve, speculative decoding, Metal's fusion ablation, per-op timings): https://github.com/Ophuscado/linux-lab/blob/master/KNOWLEDGE.md#metal-and-honeykrisp-in-detail
- The raw macOS runs (Metal and MoltenVK JSON, per-op timings, Metal's encoded graphs): https://github.com/Ophuscado/linux-lab/tree/master/results/macos
- The patches: https://github.com/Ophuscado/linux-lab/tree/master/src-patches/llama.cpp/honeykrisp
- The launch and bandwidth microbenchmarks (Vulkan and Metal): https://github.com/Ophuscado/linux-lab/tree/master/gpu/vk-chain
