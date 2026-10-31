# Facts for the next issue 10982 comment (since the 30 Oct follow-up)

For the operator's own words. One paragraph per line when pasted. Machine: M2 Ultra, 76 GPU cores, Asahi Linux, Honeykrisp with the omacom coopmat series (agxperf).

- 16x16x16 matrices: Honeykrisp lists 8x8x8 first and llama.cpp takes it. The warptile's TM/TN/TK fields set to 16 (GGML_VK_WT_M=512,128,128,,32,32,,16,16,16, no code change) give Llama 2 Q4_0 pp512/pp2048/pp4096 734/807/807 to 875/949/937 t/s, Gemma 4 817/923/867 to 858/1008/955. All MUL_MAT (2275) and MUL_MAT_ID (1109) tests pass.
- The matrix hardware itself is fast: a microbenchmark with no global memory (linux-lab gpu/vk-chain mma.comp) reaches 26.5 TFLOPS at 16x16x16 from registers and 21.3 loading A and B from shared memory, of ~27.
- The 512-token matmul's loop without its global loads runs 15.4 TFLOPS, close to what one launch of its 128 workgroups gets in that microbenchmark. The rest of the gap to Metal is the global loads not overlapping the matrix work (q4_0 4096x14336x512: 5220 us here, 3364 on Metal).
- Tried and not faster: fewer operand moves (a Mesa pass), f32 accumulators, shared-memory padding, unrolling, double-buffered tiles, B prefetched into registers.
- Two small changes that look generic, ready as PR candidates on master 5047748f1: B tiles loaded once per k step in the coopmat1 matmul (q8_0 -17 %, f16 -6 %), and the coopmat1 flash-attention shader at 2 subgroups when 4 do not fit in 32 KB (512-dim heads, Gemma 4: -22-28 %). Facts in src-patches/llama.cpp/mm-b-once and fa-2-subgroups.
- MUL_MAT_ID: the matrix-vector path past 8 tokens wins only at 1-2 tokens an expert; a per-expert limit (honeykrisp 0013) takes 64-token batches +34 % on Gemma 4 and +61 % on GPT-OSS 20B.
- Long contexts: with the core count fixed (GGML_VK_SHADER_CORES=152), Llama 2 keeps 75 % of its generation rate at 4k tokens, Metal's ratio.
- Correction to the 30 Oct offer: the MUL_MAT_ID abort with offset expert-id views happens only with the matrix-vector token limit raised (our 0002), not upstream; it is not a separate upstream fix.
