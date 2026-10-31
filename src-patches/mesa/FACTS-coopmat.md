# Facts for the coopmat series' author (omacom/mesa pull requests 3-6, commit 795ae42a71)

For the operator's own words. Machine: M2 Ultra (G14D), Asahi Linux, the series plus the agxperf commits (src-patches/mesa/agxperf).

- The hardware op is fast through the series: vk-chain mma.comp (no global memory) 26.5 TFLOPS at 16x16x16 from registers, 23.0 at 8x8x8; 21.3 / 15.7 loading 2 A and 2 B tiles from shared memory per 4 ops; B row-major 23.8 / 17.4.
- A single launch needs many workgroups: 76 groups of 256 threads 10.0 TFLOPS, 128 16.8, 1216 19.9.
- The series lists 8x8x8 first; llama.cpp takes the first shape. 16x16x16 (set through llama.cpp's warptile) gives Llama 2 prompts +18 %.
- In llama.cpp's coopmat matmul loop (8x8x8), the accumulators are scalar 16-bit phis that land on misaligned half-registers (r26h:r27l): two moves per matrix op and a ~30-move parallel copy per iteration. A pass packing 16-bit vec2 phis into 32-bit before nir_lower_all_phis_to_scalar cut the moves 73 to 57 per 16 ops, tests pass, and gave no speedup: the loop is not issue-bound.
- B fragments loaded column-major take one 16-bit load a lane (lowering's vec2 path is row-major only).
- Mesa's disassembler leaves 212-266 instructions undecoded ("XXX error") in these shaders.
- Not faster either: f32 accumulators (13-50 % slower), unrolling the k loop, shared-memory padding.
- Where the time goes: llama.cpp's matmul without global loads runs 15.4 TFLOPS at 16x16x16; with them q4_0 4096x14336x512 takes 5220 us (Metal 3364). The global loads do not overlap the matrix work; shader-side double buffering and register prefetch did not help under this compiler (the scheduler and register cost are the open question).
