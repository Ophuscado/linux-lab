# Facts for a pull request: coopmat1 matmul loads each B tile once per k step

For the operator to write the commit message and PR text in his own words (llama.cpp forbids AI-written ones; the code was drafted with an AI assistant, which the PR template asks to disclose).

- What: in mul_mm.comp's coopmat1 path, the B tiles of a k step are loaded into an array of `cms_per_col` coopmats before the A loop, instead of once per (A tile, B tile) pair. Loads from shared memory per k step drop from `cms_per_row * cms_per_col` B tiles to `cms_per_col`. The multiply-adds and their order are unchanged.
- Why it helps: the matrix units wait on shared-memory loads; with the default 2x2 coopmats per subgroup, half of the B loads were repeats.
- Cost: `cms_per_col - 1` more coopmat B registers per thread.
- Tested on master 5047748f1, Apple M2 Ultra (76 cores), Asahi Linux, Honeykrisp (Mesa with the omacom coopmat series): `test-backend-ops -o MUL_MAT` 2426/2426 pass.
- 4096x14336x512, upstream defaults, us (run 5564): f16 9985 to 9400, q4_0 8406 to 7628, q8_0 9739 to 8100, q4_K 9779 to 8986.
- In the honeykrisp series it is 0012: prompts +1-5 % on Qwen3-Coder-Next, Gemma 4, GPT-OSS 120B; Llama 2 Q4_0 even (KNOWLEDGE.md, 30 Oct).
- Not tested: NVIDIA, AMD, Intel coopmat1 drivers. The change is register-for-loads, so a driver already short of registers could lose.
