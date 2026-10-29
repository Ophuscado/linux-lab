Follow-up for issue 10982: Honeykrisp against Metal on the same M2 Ultra

Hi again! Since my last comment I booted macOS on the same Mac Studio (M2 Ultra, 76 GPU cores, 192 GB) and ran the same llama.cpp commit (2280f0f) with Metal, and with the Vulkan backend through MoltenVK. That gives a direct comparison on identical hardware, so I'm sharing the numbers in case they help.

**Tokens per second, prompt (pp512) / generation (tg128)**

| Model | Metal (macOS) | Vulkan via MoltenVK (macOS) | Vulkan via Honeykrisp (Linux) |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 120.4 | 788 / 59.9 | 763 / 69.4 |
| GPT-OSS 20B Q8_0 | 1944 / 124.5 | 992 / 82.7 | 820 / 70.4 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 67.8 | 422 / 24.8 | 448 / 34.2 |

Same settings on both systems: flash attention on, all layers on the GPU, the whole 512-token prompt in one batch, the mean of 3 runs or more. macOS 15.8.1 for the first two columns. On Linux, the patches below and Honeykrisp built from Mesa's development tree with a third-party cooperative-matrix and compiler series, with `HK_PERFTEST=designedusccdmbarrier`.

**What I take from it**

- Vulkan on macOS is no faster than Vulkan on Linux, so most of the gap to Metal is in the Vulkan backend's shaders and graph on this GPU, not in Mesa or the kernel.
- It isn't fusion: a Qwen token is 1805 Vulkan launches against 1996 Metal dispatches, and the Vulkan backend already fuses as much as Metal does. Turning fusion off drops Qwen to 24.7 t/s, so it's worth +40 % here.
- It's the cost of each dependent launch: about 4 us under Honeykrisp against 2.3 us on Metal (a microbenchmark that chains small dispatches). Averaged over a Qwen token it is ~16 us per launch on Vulkan and ~7.4 us on Metal, where about a third of the dispatches also run concurrently.
- Memory isn't the limit: a simple read shader gets 610-655 GB/s under Honeykrisp, but only ~290 GB/s when the grid has one workgroup per small slice, so many-small-workgroup shaders pay for launching them.

**Changes I tried on Linux** (a small patch series, all opt-in through environment variables)

- Medium matmul tile at 256 threads, 128x64: prompts +12-23 % (Qwen pp2048 672 to 780 t/s).
- The matrix-vector path for batches of 9-64 tokens instead of stopping at 8: a 9-token Qwen batch goes from 37 to 107 t/s, which is what makes speculative decoding pay (a code edit with ngram-mod drafts: 30 to 55-59 t/s).
- A q4_0/q8_0 matrix-vector shader laid out like Metal's kernel_mul_mv: one 4096x14336 step 81 to 68 us (q4_0) and 160 to 128 us (q8_0); generation +7 % on Llama 2, +2-4 % on Qwen. All MUL_MAT and MUL_MAT_ID tests pass.

Two of these look worth proposing on their own, and I'm happy to open pull requests if that's welcome: a fix for an abort in MUL_MAT_ID with offset expert-id views, and the 256-thread tile as Honeykrisp's default.

Everything is public, with the raw data (Metal and MoltenVK runs, per-op timings, Metal's fusion ablation, the encoded graphs) and the scripts: https://github.com/Ophuscado/linux-lab (`results/macos`, `gpu/`, `KNOWLEDGE.md`).
