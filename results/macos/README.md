# macOS reference data

Runs of [`macos/collect.sh`](../../macos/collect.sh) on the Mac Studio (M2 Ultra, Mac14,14 / J475d) under macOS 13.7.8, 14.8.9 and 15.8.1, sorted by [`macos/results-ingest.py`](../../macos/results-ingest.py) (`ingest-log.txt`). Each folder is one run, named by its start time; its `collect.log` lists its steps. Left out: Apple's compiled code (Metal libraries, shader cache, Neural Engine programs) and model files. Serial-number lines are removed, UUIDs and MAC addresses replaced. A `.alt-1` file is a second, differing copy of the same file. Files over 200 KB are gzipped (`zcat`, `zgrep`).

What the data showed: [`KNOWLEDGE.md`](../../KNOWLEDGE.md#gpu-llamacpp-on-vulkan-against-metal) (GPU, Metal) and [The Neural Engine](../../KNOWLEDGE.md#the-neural-engine).

| Step | What it holds | Runs |
|---|---|---|
| `hw` | device tree, sysctl, system_profiler, IOService nodes (GPU, ANE, DCP, SMC) | `macos-13/20261028-204051`, `macos-13/20261028-204702`, `macos-14/20261028-213234`, `macos-14/20261028-213651`, `macos-15/20261027-232820`, `macos-15/20261027-233535`, `macos-15/20261027-233602`, `macos-15/20261028-211109`, `macos-15/20261028-211514` |
| `re` | every IORegistry plane, kexts, firmware hashes, Metal device info, powermetrics samplers | `macos-13/20261028-204051`, `macos-13/20261028-204702`, `macos-14/20261028-213234`, `macos-14/20261028-213651`, `macos-15/20261027-232820`, `macos-15/20261027-233535`, `macos-15/20261027-233602`, `macos-15/20261028-004051`, `macos-15/20261028-025320`, `macos-15/20261028-031347`, `macos-15/20261028-211109`, `macos-15/20261028-211514` |
| `ane` | Neural Engine nodes, IOService entries, kext | `macos-13/20261028-204051`, `macos-13/20261028-204702`, `macos-14/20261028-213234`, `macos-14/20261028-213651`, `macos-15/20261027-232820`, `macos-15/20261027-233602`, `macos-15/20261028-211109`, `macos-15/20261028-211514` |
| `smc` | every SMC key idle, under full CPU+GPU load and after | `macos-13/20261028-204051`, `macos-13/20261028-204702`, `macos-14/20261028-213234`, `macos-14/20261028-213651`, `macos-15/20261028-055856`, `macos-15/20261028-211109`, `macos-15/20261028-211514` |
| `power` | powermetrics idle, during a prompt and during generation | `macos-15/20261027-232820`, `macos-15/20261027-233602`, `macos-15/20261028-004051`, `macos-15/20261028-025320` |
| `gpu` | metal-chain: Metal launch cost, threadgroups, matrix-vector, FMA clock | `macos-15/20261027-232820`, `macos-15/20261027-233602`, `macos-15/20261028-000231` |
| `llama` | llama.cpp with Metal: llama-bench pp512/pp2048/tg128, the 1-512 batch curve, speculative decoding, test-backend-ops MUL_MAT/MUL_MAT_ID | `macos-15/20261027-234455`, `macos-15/20261028-000105`, `macos-15/20261028-000453`, `macos-15/20261028-001045`, `macos-15/20261028-002548`, `macos-15/20261028-021506`, `macos-15/20261028-021609`, `macos-15/20261028-022802`, `macos-15/20261028-024002` |
| `ablate` | Metal fusion, concurrency and graph reordering switched off; one token's encoded graph | `macos-15/20261028-005626`, `macos-15/20261028-005632`, `macos-15/20261028-011823`, `macos-15/20261028-025200` |
| `ops` | test-backend-ops perf of the non-matmul ops | `macos-15/20261028-005626`, `macos-15/20261028-005632` |
| `vulkan` | llama.cpp's Vulkan backend on MoltenVK (llama-bench, matmul perf) | `macos-15/20261028-031227`, `macos-15/20261028-031330`, `macos-15/20261028-031339`, `macos-15/20261028-033049`, `macos-15/20261028-034346` |
| `anebench` | Core ML on CPU, GPU and Neural Engine: fp16 adds and matrix-vector timings, ane_power | `macos-13/20261028-204051`, `macos-13/20261028-204702`, `macos-14/20261028-213234`, `macos-14/20261028-213651`, `macos-15/20261028-055856`, `macos-15/20261028-063807`, `macos-15/20261028-063922`, `macos-15/20261028-193628`, `macos-15/20261028-211109`, `macos-15/20261028-211514` |
| `tbt` | Thunderbolt/USB4 as System Information reports it | `macos-15/20261028-001133`, `macos-15/20261028-001141`, `macos-15/20261028-001150` |
| `input` | Magic Mouse, Trackpad, Keyboard: HID descriptors, settings, raw reports with decoded touches per gesture | `macos-15/20261028-054146`, `macos-15/20261028-054226`, `macos-15/20261028-054537`, `macos-15/20261028-064704` |
| `display` | framebuffer properties, display profiler, ColorSync profiles | `macos-15/20261028-055856` |
| `vkchain` | vk-chain on MoltenVK (did not run: the collect.sh of that run lacked the step) | `macos-15/20261028-193628` |

`macos-15/extra/`: the Neural Engine firmware hashes of all three macOS versions, and the Thunderbolt controller dump and PCI devices with a Thunderbolt 3 box (Intel Titan Ridge) attached.

A run with one to four files is a step that failed to start (its `collect.log` says why) or a single-step rerun. Not collected yet: vk-chain on MoltenVK, and the Neural Engine benchmark's 1x1-convolution shapes (every `anebench` here is the first version: adds and `linear` layers, which Core ML planned on the CPU except at batch 64).
