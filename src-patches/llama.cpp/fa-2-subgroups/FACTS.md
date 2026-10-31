# Facts for a pull request: coopmat1 flash attention with 2 subgroups when 4 do not fit

For the operator to write the commit message and PR text in his own words (llama.cpp forbids AI-written ones; the code was drafted with an AI assistant, which the PR template asks to disclose).

- What: when the coopmat1 flash-attention shader does not fit in shared memory with its 4 subgroups, try 2 subgroups (32 key columns a block) before falling back to the scalar shader. Only for more than one query row; one row already takes the scalar path.
- Why: llama.cpp asks f32 accumulation for every model's attention (llama-graph.cpp, ggml_prec_set_acc F32). With f32 accumulators a 512-dim head (Gemma 4's global layers) needs ~34 KB at 4 subgroups. Honeykrisp offers 32 KB, so every Gemma 4 prompt used the scalar shader for those layers.
- Tested on master 5047748f1, Apple M2 Ultra, Asahi Linux, Honeykrisp: `test-backend-ops -o FLASH_ATTN_EXT` 5368/5368 pass.
- hsk=hsv=512, 8 heads, 4096 queries, us (run 5564): 8192 keys 527917 to 414093 (-22 %), 32768 keys 2607603 to 1877332 (-28 %).
- In the honeykrisp series it is 0014: Gemma 4 26B-A4B pp4096 921 to 941 t/s at depth 0, 228 to 237 at depth 16k; generation even.
- Any device with 32 KB of shared memory and coopmat1 should see the same path change for 512 heads; devices with more shared memory are unaffected (the 4-subgroup shape fits there).
