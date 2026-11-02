# Linux reference data

Runs of [`gpu/llama-compare.sh`](../../gpu/llama-compare.sh) on the same Mac Studio under Fedora Asahi Remix,
Vulkan on the Asahi GPU driver (Honeykrisp). Each `compare-*` folder is one run, named by its start time
(`driver.txt` names the Mesa build it used); `README.md`'s headline table and
[`KNOWLEDGE.md`](../../KNOWLEDGE.md#gpu-llamacpp-on-vulkan-against-metal) cite them directly.

The three `compare-20261102-*` folders are three sessions of `STEPS=bench` in a row (2 Nov, the shared GPU lock, `-t 16`), the first runs that also keep `cmake.txt`, `thermal.txt`, `models.tsv` and `provenance.json`; `python3 gpu/bench-spread.py results/linux/compare-20261102-*` shows their spread, at most 1.74 % (tg128 on Llama 2). As in the earlier folders, `model_filename` gives the home folder as `~`.

`2026-10-20-llama-bench.txt`: an early manual tuning dump (GPT-OSS 20B, `rows=1, wg=large`) from before
`llama-compare.sh` existed; superseded by the runs above. The finding it records (the large matrix-vector
workgroup, one row a workgroup for K-quants) is in KNOWLEDGE.md with later, reproducible evidence.
Kept for provenance, not cited elsewhere.
