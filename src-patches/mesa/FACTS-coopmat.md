# Facts for the coopmat series' author (omacom/mesa pull requests 3-6, commit 795ae42a71)

LLM disclosure (1 Nov 2026): This background was prepared with LLM assistance; it is not submission text. Asahi forbids generative AI for material contributions. If these facts inform an Asahi/AGX report, write it by hand and disclose the LLM assistance; otherwise, do not send it. Policy: https://asahilinux.org/llm-policy/

For the operator's own words (Asahi takes no AI-assisted material contributions; a report built from these facts is his to write). Machine: M2 Ultra (G14D), Asahi Linux, the series plus the agxperf commits (src-patches/mesa/agxperf).

- The hardware op is fast through the series: vk-chain mma.comp (no global memory) 26.5 TFLOPS at 16x16x16 from registers, 23.0 at 8x8x8; 21.3 / 15.7 loading 2 A and 2 B tiles from shared memory per 4 ops; B row-major 23.8 / 17.4.
- A single launch needs many workgroups: 76 groups of 256 threads 10.0 TFLOPS, 128 16.8, 1216 19.9.
- The series lists 8x8x8 first; llama.cpp takes the first shape. 16x16x16 (set through llama.cpp's warptile) gives Llama 2 prompts +18 %.
- In llama.cpp's coopmat matmul loop (8x8x8), the accumulators are scalar 16-bit phis that land on misaligned half-registers (r26h:r27l): two moves per matrix op and a ~30-move parallel copy per iteration. A pass packing 16-bit vec2 phis into 32-bit before nir_lower_all_phis_to_scalar cut the moves 73 to 57 per 16 ops, tests pass, and gave no speedup: the loop is not issue-bound.
- B fragments loaded column-major take one 16-bit load a lane (lowering's vec2 path is row-major only).
- Mesa's disassembler leaves 212-266 instructions undecoded ("XXX error") in these shaders.
- Not faster either: f32 accumulators (13-50 % slower), unrolling the k loop, shared-memory padding.
- Where the time goes: llama.cpp's matmul without global loads runs 15.4 TFLOPS at 16x16x16; with them q4_0 4096x14336x512 takes 5220 us (Metal 3364). The global loads do not overlap the matrix work; shader-side double buffering and register prefetch did not help under this compiler (the scheduler and register cost are the open question).
- Not only coopmat: llama.cpp's q4_K matrix-vector shader, 4096x14336 at 2 rows, takes 102 us against a 55 us read of the same 33 MB. Its loop: 339 instructions a block (64 ffma, 62 and, 48 u8_to_f, 34 shr), 16 loads, 8 waits, each wait right after its load. Replacing the arithmetic by one xor and add gives 77 us. Rewriting the shader to load first, hoist B or cut the arithmetic made it slower each time; the load scheduling looks like the compiler's to fix.

## The load hoist on G14 (1 Nov)

- `AGX_HOIST_LOADS=1` on an M2 Ultra (G14D, 76 cores, two dies), the series at 795ae42a71 with the agxperf changes: llama.cpp's test-backend-ops pass in 16 op groups (MUL_MAT 2426, MUL_MAT_ID 1109, FLASH_ATTN_EXT 5368, SOFT_MAX, RMS_NORM, ROPE, SET_ROWS, GET_ROWS, ADD, MUL, CPY, ARGSORT, TOPK_MOE, SSM_CONV, GATED_DELTA_NET).
- Generation (tg128) rises on every model tried: Llama 2 7B Q4_0 68.4 to 70.8, GPT-OSS 20B 71.3 to 74.0, GPT-OSS 120B 49.5 to 52.0, Gemma 4 26B-A4B 38.9 to 40.6, Qwen3-Coder-Next 34.7 to 37.0, Qwen3.8 Flash-Next 18.7 to 19.2. Prompts within 1 %.
- With `AGX_MESA_DEBUG=nosched` as well (what G13 gets by default), prompts lose 2-5 % here; the hoist alone is the better default for G14.
- So the hoist could default on for G14 as for G13; the facts are for the series' author, in the operator's words.
