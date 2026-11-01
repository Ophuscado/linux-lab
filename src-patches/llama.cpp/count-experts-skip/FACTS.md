# Facts for a pull request: count_experts checks the skipped mul_mat_id slots in parallel

LLM disclosure (1 Nov 2026): This background was prepared with LLM assistance; it is not submission text. Asahi forbids generative AI for material contributions. If these facts inform an Asahi/AGX report, write it by hand and disclose the LLM assistance; otherwise, do not send it. Policy: https://asahilinux.org/llm-policy/

For the operator to write the commit message and PR text in his own words (llama.cpp forbids AI-written ones; the code was drafted with an AI assistant, which the PR template asks to disclose).

- What: in `count_experts.comp`, `zero_skipped_rows` loops over every slot (n_used x n_tokens ids) in every one of the workgroup's 256 invocations. It now strides the slots over the invocations; each invocation zeroes the dst row of a skipped slot (-1 id) alone. 3 lines changed.
- Why: count_experts runs as a single workgroup before every MUL_MAT_ID, so the matmul waits on it. With 512 tokens and 10 experts used (Qwen 3.x Next) each invocation read 5120 ids one after another; the parallel loop reads 20 each. Skipped slots are rare, so the per-row zeroing by one invocation costs nothing in practice.
- Found with ggml-vulkan's per-op logger after a Honeykrisp timestamp fix: MUL_MAT_ID was 54 % of a Qwen pp512 and ran at ~150 GB/s of weights.
- Tested on master a91eab67d, Apple M2 Ultra, Asahi Linux, Honeykrisp: `test-backend-ops -o MUL_MAT_ID` 1109/1109 pass before and after (the cases with skip=1 included).
- test-backend-ops perf, MUL_MAT_ID at n=512: 128 experts of 8, m=768 k=2048: -10 % to -15 % across f32, f16, q4_0, q8_0, q4_K, q6_K, iq2_xs, iq4_xs (q8_0 4204 to 3656 us); 32 experts of 4, m=1792: -4 % to -9 % (q8_0 3632 to 3411 us; mxfp4 m=2880 k=2880 7363 to 7068 us).
- Qwen3-Coder-Next 80B-A3B Q8_0, llama-bench -fa 1 -ub 2048: pp512 413.4 to 448.0 t/s (+8 %), pp2048 627.9 to 712.1 (+13 %).
- In the honeykrisp series it is 0015 (-ub 2048): Qwen pp512 582.9 to 641.2, pp2048 743.1 to 857.7; Gemma 4 26B-A4B 834.7 to 880.9, 1005.1 to 1083.3; GPT-OSS 120B 520.7 to 541.1, 709.9 to 740.3; generation even (tg128 34.3/34.2, 38.0/38.4, 49.2/48.9).
- Measured 1 Nov under the bench's own GPU lock, not the lab's shared one: other agents' GPU work may have run
  alongside (see KNOWLEDGE.md).
- Any device gains where count_experts' serial walk is a visible share of MUL_MAT_ID; the more slots (tokens x experts used), the larger.
