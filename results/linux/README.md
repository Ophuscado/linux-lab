# Linux reference data

Runs of [`gpu/llama-compare.sh`](../../gpu/llama-compare.sh) on the same Mac Studio under Fedora Asahi Remix,
Vulkan on the Asahi GPU driver (Honeykrisp). Each `compare-*` folder is one run, named by its start time
(`driver.txt` names the Mesa build it used); `README.md`'s headline table and
[`KNOWLEDGE.md`](../../KNOWLEDGE.md#gpu-llamacpp-on-vulkan-against-metal) cite them directly.

`2026-10-20-llama-bench.txt`: an early manual tuning dump (GPT-OSS 20B, `rows=1, wg=large`) from before
`llama-compare.sh` existed; superseded by the runs above. The finding it records (the large matrix-vector
workgroup, one row a workgroup for K-quants) is in KNOWLEDGE.md with later, reproducible evidence
(runs 8529-8530). Kept for provenance, not cited elsewhere.
