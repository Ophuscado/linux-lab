# macOS reference data

Runs of `macos/collect.sh` on the Mac Studio (M2 Ultra, Mac14,14 / J475d) under macOS 13.7.8, 14.8.9 and 15.8.1,
27-28 Oct 2026, sorted by `macos/results-ingest.py` (`ingest-log.txt`). Each folder is one run, named by its start time;
`collect.log` lists its steps. Not included: Apple's compiled code (Metal libraries, shader cache, Neural Engine
programs) and model files. Serial-number lines are removed, UUIDs and MAC addresses replaced; a `.alt-1` file is a
second, differing copy of the same file from another source (mostly the log written once more on copying). Files over
200 KB are gzipped (read them with `zcat` or `zgrep`).

What the data showed is in `../../KNOWLEDGE.md` (sections "GPU: llama.cpp on Vulkan against Metal" and "The Neural Engine").

| Run | macOS | Steps | Contents |
|---|---|---|---|
| `macos-13/20261028-204051` | 13 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-13/20261028-204702` | 13 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-14/20261028-213234` | 14 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-14/20261028-213651` | 14 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-15/20261027-232820` | 15 | hw ane gpu re power | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; metal-chain: Metal launch cost, threadgroups, matrix-vector, FMA clock; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; powermetrics idle, during a prompt and during generation |
| `macos-15/20261027-233535` | 15 | hw re | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers |
| `macos-15/20261027-233602` | 15 | hw ane gpu re power | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; metal-chain: Metal launch cost, threadgroups, matrix-vector, FMA clock; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; powermetrics idle, during a prompt and during generation |
| `macos-15/20261027-234455` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-000105` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-000231` | 15 | gpu | metal-chain: Metal launch cost, threadgroups, matrix-vector, FMA clock |
| `macos-15/20261028-000453` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-001045` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-001133` | 15 | tbt | Thunderbolt/USB4 as System Information reports it |
| `macos-15/20261028-001141` | 15 | tbt | Thunderbolt/USB4 as System Information reports it |
| `macos-15/20261028-001150` | 15 | tbt | Thunderbolt/USB4 as System Information reports it |
| `macos-15/20261028-002548` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-004051` | 15 | re power | every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; powermetrics idle, during a prompt and during generation |
| `macos-15/20261028-005626` | 15 | ablate ops | Metal fusion, concurrency and graph reordering switched off (pp512, tg128) and one token's encoded graph; test-backend-ops perf of the non-matmul ops |
| `macos-15/20261028-005632` | 15 | ablate ops | Metal fusion, concurrency and graph reordering switched off (pp512, tg128) and one token's encoded graph; test-backend-ops perf of the non-matmul ops |
| `macos-15/20261028-011823` | 15 | ablate | Metal fusion, concurrency and graph reordering switched off (pp512, tg128) and one token's encoded graph |
| `macos-15/20261028-021506` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-021609` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-022802` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-024002` | 15 | llama | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding (none, n-gram 64/128, MTP), test-backend-ops MUL_MAT/MUL_MAT_ID |
| `macos-15/20261028-025200` | 15 | ablate | Metal fusion, concurrency and graph reordering switched off (pp512, tg128) and one token's encoded graph |
| `macos-15/20261028-025320` | 15 | re power | every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; powermetrics idle, during a prompt and during generation |
| `macos-15/20261028-031227` | 15 | vulkan | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) |
| `macos-15/20261028-031330` | 15 | vulkan | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) |
| `macos-15/20261028-031339` | 15 | vulkan | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) |
| `macos-15/20261028-031347` | 15 | re | every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers |
| `macos-15/20261028-033049` | 15 | vulkan | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) |
| `macos-15/20261028-034346` | 15 | vulkan | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) |
| `macos-15/20261028-054146` | 15 | input | Magic Mouse, Trackpad and Keyboard: HID descriptors and acceleration tables, settings, then raw reports, decoded touches and events per gesture (input-log.tsv) |
| `macos-15/20261028-054226` | 15 | input | Magic Mouse, Trackpad and Keyboard: HID descriptors and acceleration tables, settings, then raw reports, decoded touches and events per gesture (input-log.tsv) |
| `macos-15/20261028-054537` | 15 | input | Magic Mouse, Trackpad and Keyboard: HID descriptors and acceleration tables, settings, then raw reports, decoded touches and events per gesture (input-log.tsv) |
| `macos-15/20261028-055856` | 15 | smc anebench display | every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power; framebuffer properties, display profiler |
| `macos-15/20261028-063807` | 15 | anebench | Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-15/20261028-063922` | 15 | anebench | Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-15/20261028-064704` | 15 | input | Magic Mouse, Trackpad and Keyboard: HID descriptors and acceleration tables, settings, then raw reports, decoded touches and events per gesture (input-log.tsv) |
| `macos-15/20261028-193628` | 15 | anebench vkchain | Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power; vk-chain on MoltenVK |
| `macos-15/20261028-211109` | 15 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |
| `macos-15/20261028-211514` | 15 | hw ane re smc anebench | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC); Neural Engine nodes, IOService, kext; every IORegistry plane, kexts, firmware hashes, metal-info, sysctl, full system_profiler, powermetrics samplers; every SMC key idle, under full CPU+GPU load and after; Core ML on CPU/GPU/Neural Engine: fp16 adds and matrix-vector timings, ane_power |

`macos-15/extra/`: the Neural Engine firmware hashes of all three installed macOS versions (`ane-fw-sha256.txt`),
and the Thunderbolt controller dump (`apciec.txt`) and PCI devices (`tbt-pci-devices.txt`) with a Thunderbolt 3
enclosure (Intel Titan Ridge) attached.

Runs that ended early or repeat others are kept as they are: a run with one to four files is a step that failed
to start (its `collect.log` says why) or a single-step rerun.
Gaps, for a later macOS boot: `vkchain` never ran (the run of 28 Oct 19:36 used a `collect.sh` without the step:
"unknown step vkchain"), and every `anebench` here is the first version (adds and `linear` layers only, which Core ML
planned on the CPU except at batch 64); the 1x1-convolution shapes in the Neural Engine's own layout came later.
