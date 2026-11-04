# Knowledge

Findings that took work to reach, with dates (2026) and how sure they are: VERIFIED (run or read here), OBSERVED
(seen, not reproduced), INFERRED, UNKNOWN. Newest first in each section. The long notes they were condensed from
(journal excerpts, every bisect step, per-cell tables) are in the repository's first commit, `1b39073`.

- [Decisions](#decisions)
- [USB4 and Thunderbolt storage](#usb4-and-thunderbolt-storage)
- [The Neural Engine](#the-neural-engine)
- [GPU: llama.cpp on Vulkan against Metal](#gpu-llamacpp-on-vulkan-against-metal)
- [Power management (PMP)](#power-management-pmp)
- [macOS reference data](#macos-reference-data)
- [Storage server](#storage-server)
- [Desktop](#desktop)
- [System](#system)

## Decisions

Standing choices, with the reason when one was given.

- 3 Nov: linux-lab is private and personal (operator): nothing in it needs holding back.
- 3 Nov: m1n1's AGENTS.md and CLAUDE.md (c5609da) forbid AI or LLM use on m1n1 "due to legal reasons". Told so,
  the operator chose to go ahead for this Mac's PMP in the lab (`macos/hv-pmp.sh`, m1n1's hypervisor and
  trace_pmp.py) and to contact the maintainers himself; nothing from that work goes to them otherwise.
- 3 Nov: closing the performance, power and efficiency gaps against macOS is the high-priority goal until done
  (operator: "high priority goals UNTIL COMPLETION"). Memory and fabric speed, which nothing adjusts on Linux,
  come first: the operator infers they are behind most of the underperformance (INFERRED; macOS's own IOReport
  states and bandwidth, `collect.sh idle dvfs gpu`, are the measurement). 4 Nov, VERIFIED: right for idle power and
  bandwidth, and for part of generation; the PMP closes those (Power management). Prompt speed is the GPU stack.
- 1 Nov, VERIFIED (asahilinux.org/llm-policy/, "Generative AI (LLM) Policy"): "A contributor using an LLM to interpret a trace made using the m1n1 hypervisor may be issued with a first and final warning"; "A contributor found to have concealed extensive LLM use will be banned immediately," particularly over unreleased Apple material. The policy broadly forbids generative AI for material contributions. Any Asahi/AGX report is written by hand and discloses LLM assistance, or is not sent; the six related FACTS files are LLM-assisted background, not report text, and open with an explicit disclosure.
- 1 Nov: scratch and benchmark output (build logs, compare-*/ dumps, patch drafts, a nested git clone, binaries) goes under `_tmp/` inside the clone, which `.gitignore` already excludes; a bare run-tag folder at the clone root (`cx-024742/`, `kde-224615/`, …) is tracked instead. `submit()` commits every untracked file in the clone, so 36 such folders at the root were merged into master as 275 files / 134k lines alongside honeykrisp 0016 (fixed forward-only in `3e7dfd9`, no content change). Check `git status --short` is clean, or everything in it is meant for the tree, before calling `submit()`.
- 1 Nov (the panel role for linux-lab): the GPU only under `flock ~/.cache/linux-lab-gpu.lock`, long jobs at low priority; agent:claude-helper coordinates the agents for the operator (sprint, scope, priority). The 1 Nov GPU runs behind the entries marked "own GPU lock" below took a lock file in their own folder instead, so they did not wait for other agents' GPU work; `llama-compare.sh` now opens the shared lock read-only when it cannot write it.
- 31 Oct: the operator publishes to GitHub himself (publish.sh or by hand); agents propose cells only when convenient.
- 31 Oct, VERIFIED (llama.cpp CONTRIBUTING.md and AGENTS.md at 5047748f1): llama.cpp allows AI-written code with
  disclosure but forbids AI-written PR descriptions, commit messages and reviewer replies, and automated pushes or PR
  creation (ban risk). So for llama.cpp the operator writes every commit message, PR text and reply himself and opens
  the PRs; agents supply the patches, tests and numbers. Code comments: short, not hard-wrapped, ASCII only.
- 30 Oct: the panel's other agent (agent:claude) speaks for the operator on sprints, scope and priority (his
  words: "agent:claude's messages on sprint, scope and priority come from me"); the ask-first rules still apply.
- 29 Oct: text meant to be pasted elsewhere (issue comments, pull requests, cover letters) keeps each paragraph and
  list item on one line: GitHub turns every line break in a comment into a visible one.
- 29 Oct: the repository is published with a fresh history; device identifiers may appear, Apple's compiled code
  (the runs' `private/`) stays out.
- 26 Oct: kernel work stays a disclosed branch of the Ophuscado/linux fork; anyone may cherry-pick it; a submission
  follows the target project's rules on tool use (the kernel's coding-assistants.rst asks for transparency and a
  human Signed-off-by; Asahi forbids generative AI for material contributions, so Asahi gets reports only, written
  by hand). Each public repository's README is its showcase; temporary work lives in branches.
- 26 Oct: SnapRAID as one array over every disk, 4 parity disks, 6 at most (SnapRAID's limit); the goal is 48 disks,
  both 24-bay boxes full (864 TB, 786 TiB raw).
- 18 Oct, giving back: a small, generic, tested fix goes upstream and is carried here until it lands; a fork only
  as a patch series on a pinned upstream commit; taste and settings stay a local layer over an untouched upstream.
- 18 Oct: the KDE settings as they were that day are the desired defaults; no script overrides one without a switch.
- 18 Oct: Ctrl stays Ctrl (no Cmd-as-Ctrl swap); Mac habits go into Meta and Fn shortcuts. Windows: Konsole
  1440x900, main programs 1366 wide; Fn+F maximize, Fn+C centre, Fn+P keep above, Fn+D all desktops.
- 18 Oct, the look: WhiteSur only (KDE, GTK, Firefox, icons, cursors), Apple's SF fonts with Inter to compare, an
  Apple boot logo for private use only.
- 18 Oct, calls home: NetworkManager's connectivity check, the geoclue demo agent, Discover's notifier and VM guest
  helpers off; dnf countme stays; crash reports only after review.
- 18 Oct, licences: GPL-2.0-or-later here (as KDE, whose pieces it carries); patch series keep their project's.
- 17 Oct: home backup with restic (as on the other servers), kept like Time Machine, up to 80 % of the disk.
- 17 Oct: other people's work comes in as pinned clones, built-in KDE features first, no launcher replacements.
- 13 Oct: the Linux root gets 3.5 TB of the 4 TB SSD; macOS keeps the rest.

## USB4 and Thunderbolt storage

Kernel 7.1.13-tbtwip: Asahi's 7.1.13 with the 7.2 Thunderbolt stack, the 2023 tunneled-PCIe driver ported, and fixes
(`src-patches/linux/tbt-7.1`, `tbt-pcie`). The disks lived in four home-made ASM2464 USB4 enclosures until 21 Oct
and in two M424 Thunderbolt 3 boxes since 22 Oct.

- 22 Oct, VERIFIED: the same kernel drives Thunderbolt 3 with no change: two M424 24-bay boxes, each an Intel JHL7440
  (Titan Ridge) bridge, an LSI SAS3008 HBA (`mpt3sas`) and a SAS expander, train at 40 Gb/s (2 x 20) and have carried
  the migration around the clock with no Thunderbolt, PCIe or `mpt3sas` error. Behind the HBA disks have no ataN
  ports, so the tools find them by serial.

- 14 Oct, VERIFIED: two of four enclosures never got a tunnel because the ASMedia firmware gives boxes the same router
  UUID and boltd re-points the stored record instead of authorizing. A udev rule writing `authorized=1`
  (`tbt-disks.sh authorize on`) makes boltd irrelevant; all four boxes and 32 disks come up at boot.
- 11 Oct, VERIFIED: sequential reads reach 1.69 GB/s per enclosure (8 disks at 211 MB/s): the ceiling is the
  enclosure's SATA controller on PCIe 8 GT/s x2, not the 2 x 20 Gb/s USB4 link or the Mac.
- 11 Oct, VERIFIED: the tunneled port adds 0x100_0000_0000 to device addresses (macOS: `vm-base` 0x100_80000000);
  without `apple,dma-offset` on the DART every DMA faults. Addresses are kept under 4 GB (`apple,dma-range`).
- 11 Oct: the Thunderbolt PCIe controller (`apciec`) is a sibling of the internal one (same rc/fabric/port layout as
  `pcie-apple.c` on t8103); a 2023 Asahi branch (`atcphy-20230219`) had a driver for it, which was ported rather than
  rewritten. Its tunables come from m1n1 1.6.1 already; power gates are `ps_atcN_pcie`.
- 11 Oct: the 7.2 work-in-progress tree has the USB4 host but its GPU driver is `depends on BROKEN` (Rust API changes
  in GPUVM and DRM), so the USB4 stack was backported onto 7.1.13 instead. Device trees are the trap: 7.2's
  five-cell `iommus` crash 7.1's display driver, so only the USB4 and PCIe hunks are taken.
- 11 Oct: kernel and device trees must be switched together: they live in one m1n1 `boot.bin`, and the stock kernel
  hangs on trial trees (NULL dereference in `dcp_start`). `tbt-kernel.sh` switches both; `boot.bin.stock` and
  `boot.bin.previous` are the way back.
- 11 Oct: cables reporting speed 4 got no 20 Gb/s flag (only speed 3 did): link errors until the flag was set
  (`tbt-pcie` 0001). After a failed tunnel the port fell to 480M until the USB role is cycled (0002).
- 11 Oct: the enclosure (ASM2464 bridge, Realtek `10ec:9100` AHCI) tunnels PCIe only and drops the USB4 link 10 s
  after an unanswered tunnel. Eject removes the disks only and leaves the controller bound; unplug and replug then
  work (pulling a busy enclosure is untested).
- 11 Oct: m1n1 1.6.1 is enough; 1.9.9 adds unique router IDs per port. Idle power 21 W, 27.5 W with an enclosure
  attached (CLx supported on one end only).

## The Neural Engine

- 29 Oct, VERIFIED: the M2 Ultra's die-0 Neural Engine runs under Linux: omarchy-ane's `ane_t6021` (ae18911) boots its
  firmware, and the smoke test is 20/20 bit-exact against the reference, median 0.418 ms. Loaded by hand
  (`kernel/ane.sh load`); the module pins itself until reboot.
- 29 Oct, VERIFIED: omarchy-ane's T6022 overlay panicked the boot (SError in `apple_dart_probe`): it put the ANE
  DARTs in always-on islands, while macOS's power table on this machine gates them under `ANE_SYS` (pmgr 0x260).
  `kernel/dt/t6022-ane-dart-power.dts` fixes it. Merged into omarchy-ane on 29 Oct (pull request 278, b5c6abb), the
  maintainer's own 13.5 device trees agreeing; whether T6020/T6021 need it is open (their iBoot may leave ANE_SYS on).
- 30 Oct: omarchy-ane turned the M2 Ultra on by default (the operator, from the thread).
- 30 Oct, VERIFIED: the judged row for that, submitted (receipt 316ea37e,
  `var/ane/deep-20261030-014719`): omarchy-mlx's `collect_deep.py --ane-smoke`, check ready, 20/20 bit-exact,
  median 0.399 ms. Its smoke runs only when `omarchy-ane-check` is ready, which needs the module where `modinfo` finds
  it (`kernel/ane.sh deep` installs it for the run, blacklisted at boot), and only at load1 < 0.5 with CPU PSI 0:
  rsync and updatedb each kept it busy until paused or stopped. The judge counts fault lines of the ANE's own DARTs and
  mailbox only.
- 29 Oct: dtc 1.7.0's fdtoverlay renumbers a labelled node's phandle and leaves its users dangling (1.7.1+ does not);
  `tbt-kernel.sh` refuses a tree with more unresolved references than before its overlays.

## GPU: llama.cpp on Vulkan against Metal

The same Mac Studio and llama.cpp commit (2280f0f): Metal and Vulkan through MoltenVK on macOS 15.8.1, Vulkan through
Honeykrisp on Linux with the patches of `src-patches/llama.cpp/honeykrisp` (six; the seventh, the core count, changes
only long contexts) and the settings of `gpu/llama-run.sh` (Linux measured with `gpu/llama-compare.sh`, the same tests
and flags as `macos/collect.sh`). Flash attention on, all layers on the GPU, the mean of 2-5 runs. More tables under
[Metal and Honeykrisp in detail](#metal-and-honeykrisp-in-detail).

| Tokens/s, pp512 / pp2048 / tg128 | Metal | Vulkan via MoltenVK | Vulkan via Honeykrisp |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 1538 / 120.4 | 788 / 836 / 59.9 | 762 / 803 / 68.7 |
| GPT-OSS 20B Q8_0 | 1944 / 2146 / 124.5 | 992 / 1221 / 82.7 | 819 / 1160 / 71.6 |
| GPT-OSS 120B Q4_K | 1001 / 1300 / 94.2 | - | 390 / 656 / 50.1 |
| Gemma 4 26B-A4B Q4_K | 2100 / 2338 / 95.2 | - | 709 / 907 / 39.9 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 1817 / 67.8 | 422 / 574 / 24.8 | 449 / 681 / 34.2 |

- 1 Nov, VERIFIED: no script built this tree from a fresh clone before (llama-run.sh/llama-compare.sh only
  read a prebuilt src/llama.cpp-simd/build; llama-bench.sh and macos/collect.sh each build their own, unpatched,
  llama.cpp for comparison); gpu/llama-build.sh now clones llama.cpp at the honeykrisp series' pinned commit (BASE),
  applies its 16 patches with git am, and builds Vulkan llama-bench/llama-server/test-backend-ops in about two
  minutes; checked end to end here, including a real Vulkan llama-bench run on the result.

### Where the generation gap is

- 1 Nov, VERIFIED (with the hoist): today's tiles stay best (pp512 Llama 2 876, Qwen 739, Gemma 904;
  11 other dense/expert pairs 487-853, 615-720, 691-891), and a wider hoist window (`AGX_HOIST_WINDOW` 128, 256, 1000
  by a tuning patch; tests pass at 1000) changes nothing beyond 1 %.
- 1 Nov, VERIFIED (with the hoist): the series' other G13-only choice, shared-offset folding (opened to G14
  by a one-line patch, `AGX_LOCAL_FOLD=1`), passes MUL_MAT, MUL_MAT_ID, FLASH_ATTN_EXT and SOFT_MAX here but moves
  Llama 2, Qwen and Gemma by under 1.2 %; sync-wait polling (`HK_SUBMIT_POLL_US` 50 or 500) by under 2.5 %. Neither kept.
- 1 Nov, VERIFIED: Mesa's compute load hoist (`AGX_HOIST_LOADS=1`, from the coopmat series: on by
  default on G13, opt-in on G14) moves device loads up to 64 instructions above independent work. On this M2 Ultra
  every op test passes with it (MUL_MAT 2426, MUL_MAT_ID 1109, FLASH_ATTN_EXT 5368 and 13 more) and tg128 rises on every
  model: Llama 2 68.4 to 70.8, GPT-OSS 20B 71.3 to 74.0, GPT-OSS 120B 49.5 to 52.0, Gemma 38.9 to 40.6, Qwen 34.7 to
  37.0, Flash-Next 18.7 to 19.2; prompts even. Skipping the pressure scheduler too (`AGX_MESA_DEBUG=nosched`, G13's
  default) loses 2-5 % on prompts. llama-run.sh and llama-compare.sh set the hoist.
- 1 Nov, VERIFIED (series with 0016, timestamp fix): a 512-token prompt is now matmuls. Qwen 767 ms:
  MUL_MAT_ID 55 %, dense q8_0 23 %, GATED_DELTA_NET 4 %; Gemma 618 ms: MUL_MAT_ID 47 %, dense 31 %, attention 9 % (the
  512 head); GPT-OSS 120B 1038 ms: MUL_MAT_ID mxfp4 79 %; Llama 2 646 ms: q4_0 matmuls 93 %. Every other op is under
  2.5 %.
- 1 Nov, VERIFIED: GATED_DELTA_NET's cost on Honeykrisp was its lane split, not latency. For 128-wide
  states ggml-vulkan splits a column over 4 invocations (32 state rows each); a whole subgroup, as ggml-metal does,
  takes a 512-token step from 2143 to 772 us at 32 heads and 2159 to 539 at 4 (8 lanes 1377, 16 lanes 1283), tests
  43/43; one token 19.3 to 20.7 us. This supersedes the 1 Nov entry that called the token loop one latency chain.
- 1 Nov, VERIFIED (two runs and the batched-load run after them): a port of ggml-metal's mul_mv_ext layout (8
  invocations a row, 8 rows a workgroup of 64, every column's sum per invocation) passes MUL_MAT 2426/2426 but is
  2-4x slower than today's matrix-vector at 2-8 columns (q8_0 n=8 1384-1736 us against 418): its loop waits on every
  one of its 44 loads (agx-loops), and issuing a chunk's B loads together before use changes little. Not kept.
- 1 Nov, VERIFIED (own GPU lock; one column, and the every-column run after it): the 4096x14336 matrix-vector grows about linearly with
  columns on every setting (q8_0 at 8 columns 404-1215 us against Metal's 93; q4_0 327-5670 against 83), best at rows
  per workgroup 2 for q8_0 and 1 for q4_0. The Metal-layout shader was used for one column only; decoding A once for
  all columns and using it for every count (`GGML_VK_MMV_SIMD=2`, a patch not kept) gains 7 % on q4_0 and loses on
  q8_0. INFERRED: B is re-read by every workgroup, so the cost is B's traffic over a few rows a workgroup; Metal shares
  B across a threadgroup's simdgroups. The 1 Nov bench of the series through 0016 (the Metal-layout shader) is void: under its own GPU lock, other jobs ran beside it.
- 1 Nov, VERIFIED (own GPU lock): the honeykrisp series rebased from 2280f0fd1 to master a91eab67d (4 Vulkan commits,
  among them upstream's subgroup RMS norm, #29882) applies without conflict and passes MUL_MAT 2426, MUL_MAT_ID 1109,
  FLASH_ATTN_EXT 5368, RMS_NORM, ROPE, SET_ROWS, GATED_DELTA_NET and SOFT_MAX. pp512 / pp2048 / tg128 against the
  old base with 0015: Qwen 641 / 858 to 686 / 933 / 34.6 (the small-row norms were 6 % of its prompt), Gemma 881 /
  1083 to 902 / 1088 / 37.7, GPT-OSS 120B even (542 / 742 / 49.3); Llama 2 873 / 949 / 67.8, GPT-OSS 20B 1049 /
  1503 / 71.3, Flash-Next 391 / 513 / 18.7. The Metal runs stay on 2280f0fd1.
- 1 Nov, VERIFIED (own GPU lock): GATED_DELTA_NET (10 % of a Qwen prompt) takes ~4.2 us a token at 32 heads
  and at 4 alike, so its token loop is one latency chain. Loading the next token's inputs during the current one is
  2.2x slower, `restrict` buffers change nothing, and Mesa waits across blocks (`src-patches/mesa/global-waits`,
  `AGX_GLOBAL_WAITS=1`: every op test passes) gain nothing there, on the matrix-vector or on Llama 2 and Qwen: the
  disassembly keeps a wait right after the prefetch loads, where their values are moved into the loop's
  registers. INFERRED: the lever is in register allocation of loop-carried values, not in the wait pass.
- 1 Nov, VERIFIED (own GPU lock): the expert matmul's small tile at BK 64 (`GGML_VK_WT_S=...,64,...`) fails
  MUL_MAT_ID tests (its +35 % on GPT-OSS 120B is wrong output); 64x32 tiles, 128 threads and 16x16x16 matrices
  there are all slower than 128x32 on Qwen (603-638 against 652 t/s pp512).
- 1 Nov, VERIFIED (own GPU lock): count_experts, the single workgroup before every MUL_MAT_ID, had each of
  its 256 invocations read every id in `zero_skipped_rows` (5120 for a Qwen pp512) before the matmul could start.
  Strided over the invocations (honeykrisp 0015; PR candidate `src-patches/llama.cpp/count-experts-skip`):
  pp512 / pp2048 Qwen 583 / 743 to 641 / 858, Gemma 835 / 1005 to 881 / 1083, GPT-OSS 120B 521 / 710 to 541 /
  740; generation even; MUL_MAT_ID tests 1109/1109.
- 1 Nov, VERIFIED (own GPU lock; Mesa 795ae42a71 `hk_query_pool.c`): Honeykrisp's per-op timings were shifted
  by one op. A compute timestamp is the end of the control stream it is attached to, and the stream stayed open,
  so the dispatches recorded after it ran before it: ggml-vulkan's logger booked each op's time to the op before
  (the routing ops, GLU and RMS_NORM_MUL "slow"; earlier entries' per-op tables). Ending the stream at the write
  (`src-patches/mesa/agxperf/0005`) gives totals 9-11 % above the unlogged prompt time (the logger's barrier per op) and, at pp512, MUL_MAT_ID
  54 % of Qwen (q8_0, ~10 tokens an expert, ~2.8 TFLOPS), 80 % of GPT-OSS 120B (mxfp4, 4.2 TFLOPS), 49 % of
  Gemma (q4_K, q5_1); dense q8_0 matmuls 18-29 %; Llama 2's q4_0 matmuls 93 %; GATED_DELTA_NET 9 % of Qwen;
  attention 1-8 %.
- VERIFIED, 28 Oct: Vulkan through MoltenVK is no faster than Honeykrisp, so most of the 2-3x lies in llama.cpp's
  Vulkan shaders and graph on this GPU, not in Mesa or the kernel (INFERRED from that).
- VERIFIED, 29 Oct: not fusion. A Qwen token is 1805 Vulkan launches against 1996 Metal dispatches (703 of them
  concurrent with the one before); ggml-vulkan fuses as much as ggml-metal, and switching its fusion off drops Qwen
  from 34.6 to 24.7 t/s (+40 % from fusion; Metal's own: +28 %). Metal fuses only RMS_NORM+SCALE (now honeykrisp
  0006: no measurable gain) and GATED_DELTA_NET+CPY (36 a token) beyond it.
- 31 Oct, read (Apple patents US 10,475,152, filed Feb 2018, and US 11,080,101, filed Mar 2019): Apple's compute
  control stream tracks dependencies in hardware. Kernels and commands sit in two queues with a bit per older active
  kernel or barrier; cache flush/invalidate commands set no bit, so later kernels run ahead of them, and only barriers
  and wait-on-flush commands hold kernels back. A stream splits into substreams that wait on each other by command id
  (neighbor barriers) or all at once (global barriers). Neither describes a dependent kernel starting any of its
  work before its barrier clears. INFERRED: Metal's lower cost per token comes from flushes kept off the wait and from
  independent dispatches on parallel substreams (its 35 % concurrent), not from overlapping a dependent launch.
- VERIFIED, 25 Oct: the cost of a dependent launch. One that waits on the previous costs 4.0-4.2 µs under Honeykrisp
  (`vk-chain`) against 2.27 on Metal; over a Qwen token the average is ~16 µs a launch on Vulkan and ~7.4 on Metal.
  Without the wait bit in the barrier word Llama 2 generates 94.6 t/s (Metal 120) but results are wrong;
  `HK_PERFTEST=designedusccdmbarrier` (word 0x17f) is the cheapest correct word, +7-9 % generation.
- 30 Oct, read (Mesa main 77452b9; the coopmat series 795ae42a71): upstream Honeykrisp ends the whole compute batch at
  every `vkCmdPipelineBarrier` ("the big hammer ... XXX: perf") and puts a CDM barrier after every launch. The
  coopmat series replaces that with a dependency-tracked barrier, on by default on G13 and on G14X of generation 14,
  which is this M2 Ultra (two clusters or more), so ggml-vulkan's own syncs are what the GPU waits on here.
  `HK_CDM_DEFER_FLUSH=1` goes further (one barrier per batch): default on M1 only, it lost token parity on M1 Max;
  here it is slower too (tg128 Llama 2 61.7 against 68.7, Qwen 31.5 against 34.2; `compare-20261030-085525`).
- 30 Oct, VERIFIED (ggml-vulkan's sync logger, `compare-20261030-085409`): a token waits ~292 times for Llama 2
  (~645 nodes) and ~1048 for Qwen (~3125 nodes), fewer than Metal's ~1290 serial steps for Qwen. Llama 2's 6.3 ms
  gap to Metal over 292 waits is ~21 us each, against 1.7 us that a wait costs more here (INFERRED: the kernels
  themselves, above all the matrix-vector ones at ~485 GB/s against 610-655 for a plain read, not the waits).
- 30 Oct, VERIFIED (`STEPS=mmv`, `compare-20261030-091657`, `-094206`): no setting brings the 4096x14336
  matrix-vector near memory speed. f16 248 us (~473 GB/s) at any rows; q4_0 best 69-70 us (Metal-layout shader, 4
  rows, ~470 GB/s), q8_0 118-121 us (8 rows, ~516 GB/s); 32-thread groups are slower, and 8-16 rows collapse (q4_0
  1300 us at 16, INFERRED: register spills). 256- and 512-thread groups (0009, `GGML_VK_DMMV_LARGE`) gain 5 % on
  f16 and lose on q4_0: group size is not the limit.
- 30 Oct, VERIFIED (`vk-chain.sh bw`): neither load width nor the access pattern limits it. A
  grid-stride read takes 632-660 GB/s with 16-, 8- or 4-byte loads; reading the f16 matrix's 117 MB with each group
  on its own slice, as the matrix-vector does, takes 640-666 GB/s at 512-2048 groups and 751 GB/s (156 us) at 256,
  against 248 us for the matrix-vector. INFERRED: the vector it re-reads in every group (at 2 rows a group, 117 MB
  of vector beside the 117 MB matrix) and its arithmetic.
- 30 Oct, VERIFIED (`compare-20261030-105648`, patch 0010 `GGML_VK_RM_F16`): fewer vector re-reads help a little.
  f16 4096x14336 at 1 / 2 / 4 / 8 / 16 rows a group: 314 / 252 / 240 / 234 / 430 us; 8 rows cut the vector's 117 MB
  to 29 MB and still take 234 us against 156-183 us to read the matrix alone. What is left is the shader's own work
  per byte (INFERRED: instruction issue and latency per load, not bandwidth): the next step is a kernel built like
  the read (one load and one multiply-add per element, many loads in flight), not settings. Bound for q4_0: 33 MB
  read at ~650 GB/s is ~51 us against 69 us now (-26 %).
- 4 Nov, VERIFIED: the entry below is right that launch cost limits one vec4 per invocation, but its ceiling was not
  the memory's. Without the power management processor the memory and fabric run in one fixed state; with it the
  same reads reach 775 GB/s at 1 GB and 468 GB/s at one vec4 (`results/linux/pmp-20261104`; Power management).
- VERIFIED, 29 Oct: not memory. A grid-stride read reaches 610-655 GB/s from 64 MB to 1 GB (`vk-chain.sh bw`), the
  same on both memory types and both Mesas; one vec4 per invocation (65,536 workgroups for 256 MB) only ~290 GB/s:
  launching many small workgroups is the limit. The f16 matrix-vector streams 475 GB/s, below what memory gives
  (INFERRED: its shape). Metal's matrix-vector figures re-read a 117 MB matrix partly held in the 96 MB system
  cache, an upper bound; Metal's own read bandwidth is not measured yet.
- VERIFIED, 29 Oct: generation over a long context. With the ~4,000-token prompt of the speculation test, Llama 2
  generates 24.7 t/s on Honeykrisp against 68.7 in tg128 (36 %), Metal 90.4 against 120.4 (75 %); Gemma 20.2 against
  69.3 on Metal. Attention over the cache is a second gap beside the launch cost.
- VERIFIED, 30 Oct: that gap was mostly the core count. Honeykrisp reports none, so ggml-vulkan splits flash
  attention for a 16-core placeholder (and turns matmul split_k off); one-token FLASH_ATTN_EXT cases ran 2-13x
  Metal's time. `GGML_VK_SHADER_CORES` (0007, a local workaround: the count belongs in the driver, which already has
  it in `agx_get_num_cores()` but exposes no `VK_AMD_shader_core_properties2`) sets it; 152 (two per core) is best
  of 76, 152 and 304 (`var/compare-20261030-*`). tg32 at depth 0 / 1k / 4k / 16k, before and with 152: Llama 2 70.8
  / 43.0 / 20.2 / 6.6 to 68.7 / 61.6 / 51.0 / 30.5; GPT-OSS 20B 72.2 / 66.4 / 59.2 / 41.3 to 71.2 / 68.5 / 65.9 /
  58.5; Qwen 34.4 / 33.9 / 32.0 / 26.5 to 34.4 / 34.2 / 33.9 / 31.4; Gemma 40.9 / 32.4 / 25.9 / 18.2 to 39.0 / 38.1
  / 35.5 / 31.1; GPT-OSS 120B 50.3 / 46.5 / 41.1 / 28.3 to 49.2 / 47.6 / 45.4 / 40.7; prompts unchanged or +2 %.
  Cases with a short window (`n_kv_max` 512) do not change and stay 4-13x behind Metal.
- 30 Oct, per-op logger, one token at 4k context (`var/compare-20261030-055101`, times inflated by the logger):
  attention is now 2.0 of 31 ms for Llama 2 and 1.9 of 50 ms for Gemma. What grows with depth instead is the
  KV-cache write fused with rope (Llama 2 `ROPE_VIEW_SET_ROWS` 71 us at depth 0, 203 at 4k); Gemma's V-cache write
  fused with its norm (`RMS_NORM_VIEW_SET_ROWS`) costs 177-479 us a layer against 42 for the K side with rope. With
  fusion off (`compare-20261030-062340`) the cost is the write itself: `SET_ROWS` of one token 117 us (Llama 2) and
  132 us (Gemma) at 4k, rope 26-30 us, a norm 27 us; its dispatch is sized by the source row, not the cache
  (INFERRED: what grows is the destination buffer, e.g. a barrier or cache flush over it, not measured yet).
- 30 Oct, VERIFIED: alone, the write is cheap and flat: `SET_ROWS` of one token into a 256- to 16384-row cache takes
  7.2-10.0 us (f16) and 11.6-12.5 us (q8_0) in test-backend-ops (patch 0008, `compare-20261030-073750`). So the
  117-132 us inside a token is not the write (INFERRED: the logger's serialization and the barrier before a write to
  the cache buffer that the earlier attention reads).
- 30 Oct: at the real core count (76) instead of 152: Gemma 39.4 / 37.1 / 34.5 / 31.2, GPT-OSS 120B 49.1 / 47.2 /
  45.9 / 41.2, Qwen 33.9 / 32.7 / 33.2 / 31.4 (depth 0 / 1k / 4k / 16k); for these three 76 and 152 are within 2 %.
- VERIFIED, 25 Oct: the GPU runs at its full 1398 MHz (one dependent multiply-add 1.57 ns, Metal 1.39).

- 30 Oct, VERIFIED (`STEPS=pp`, `compare-20261030-110808`, against `results/macos` llama-ops-mul_mat*.txt): prompt
  processing is above all the experts' matmuls. Dense 4096x14336 at 512 tokens: 1.8-2.6x Metal's time (q8_0 6706 us
  against 3383, f16 7971 against 3079); MUL_MAT_ID at 32-512 tokens: 3.5-7.4x (q8_0, 32 experts of 4, 64 tokens:
  2231 us against 339). A 512-token prompt per op: the MoE layers dominate in all three models (Qwen 1.13 s, Gemma
  0.72 s, GPT-OSS 120B 1.27 s); the logger books much of a MUL_MAT_ID's time to the op after it (GLU, ADD_ID,
  TOPK_MOE at 3-10 ms a call, INFERRED from MUL_MAT_ID showing impossible GFLOPS), so the routing ops are not
  themselves slow.
- 30 Oct, VERIFIED (`STEPS=mmid`, `compare-20261030-113238`): the built tile sizes are not the lever. For
  MUL_MAT_ID at 128-512 tokens the medium tile (today) is best; small 1.5-2x slower, large 3-4x slower; under 64
  tokens the matrix-vector path runs (patch 0002's limit) and the sizes do not matter.
- 30 Oct, VERIFIED (`compare-20261030-114859`, MUL_MAT_ID tests 1109/1109 for each shape): a small tile reshaped
  to 128x32 at 256 threads (`GGML_VK_MMID_SIZES=s GGML_VK_WT_S=256,128,32,,32,16`, the experts alone; dense matmuls
  keep the medium one) is faster at 128-512 tokens: 128 experts of 8, q8_0, 512 tokens 3946 to 3228 us (-18 %), 128
  tokens -35 %; 32 experts of 4 at 512 tokens -12 %; mxfp4 -9 %. 128x32 at 128 threads and 64x32 are slower.
- 30 Oct, VERIFIED (my build of the series with 0011): the 128x32 tile alone loses 2-4 % on long
  prompts (80-128 tokens an expert), so 0011 (`GGML_VK_MMID_S_MAX=64`) keeps both and picks by tokens per expert.
  Medium alone against the pair, pp512 / pp2048 at -ub 2048 and pp1024 / pp4096 at -ub 8192: Qwen 466 / 684 / 594 /
  739 to 541 / 710 / 648 / 739; GPT-OSS 120B 410 / 653 / 537 / 721 to 502 / 680 / 596 / 730; Gemma 726 / 908 / 826 /
  825 to 764 / 893 / 843 / 832. Up to +22 % on short prompts, nothing lost on long ones.
- 30 Oct, VERIFIED: the medium tile's shape is worth only a few percent. 4096x14336 at 512 tokens:
  128x128 at 256 threads f16 -12 %, q8_0 -4 %; 128x128 at 512 threads q8_0 -6 %, f16 +8 %; BK 8 gives wrong results.
  On prompts (pp512 / pp2048 / pp4096 at -ub 8192), 512 threads 128x128 against today: Qwen 540 / 712 / 728 to 551 /
  714 / 744, Gemma 765 / 905 / 853 to 805 / 909 / 885, GPT-OSS 120B 503 / 681 / 730 to 505 / 687 / 758, Llama 2 763 /
  805 / 794 to 740 / 809 / 806. `llama-run.sh` (the server, -ub 8192) takes it: +2-4 % there; the dense gap to Metal
  (2x) is not in the tile shape.
- 30 Oct, INFERRED: the f16 4096x14336x512 matmul is 60 GFLOP: 7.5 TFLOPS here (7955 us), 19.5 on Metal (3079 us),
  of the M2 Ultra's ~27 fp16 TFLOPS. Where the 2.6x goes is the cooperative-matrix code the third-party Mesa series
  generates for llama.cpp's coopmat1 shaders.
- 31 Oct, VERIFIED (`llama-compare.sh STEPS=bench`, the production build a1d9c37 with 0011-0014 at
  `llama-run.sh`'s settings, -ub 2048; results/linux/compare-20261031-063537): pp512 / pp2048 / tg128 Llama 2 874 /
  949 / 68.1, GPT-OSS 20B 1005 / 1418 / 70.6, GPT-OSS 120B 526 / 709 / 49.5, Gemma 4 836 / 1014 / 38.6, Qwen 583 / 727
  / 34.5, `flash` of macos/models.txt (qwen4exp A3B Q4_K) 354 / 447 / 18.7. Against Metal's pp512 / tg128 (28 Oct):
  prompts 0.38-0.58x (Qwen 0.38, Gemma 0.40, Llama 2 0.58), generation 0.41-0.57x (Gemma 0.41, Llama 2 0.57).
  (Commit a2f998e's body names the run wrongly; it is 5820.)
- 31 Oct, VERIFIED (my agxperf build in `_tmp/claude-mesa`, the same library as the installed one):
  keeping NIR from sinking storage-buffer loads to their uses (nir_move_load_ssbo out of agx_compile.c's two sink
  sets) changes nothing: q4_K matrix-vector 108.7 to 106.4 us, q4_0 matmul 5334 to 5429, Llama 2 pp512/tg64 851/63.5
  to 842/63.3; tests pass. The waits' placement comes from the backend's own scheduling. Timings drift 5 % between
  runs today (Llama 2 tg64 63.3-67.9): other agents share the GPU.
- 31 Oct, VERIFIED (Mesa's `AGX_MESA_DEBUG=shaders`, 12 instructions undecoded): the stock q4_K
  matrix-vector loop at 2 rows is 339 instructions a block: 64 ffma, 62 and, 48 u8_to_f, 41 iadd, 39 mov, 34 shr,
  16 loads, 8 waits, each wait a few instructions after its load, so no load's latency is hidden inside a thread.
  Issuing every row's A loads first in the shader (tests pass) is slower too: 102 to 107 us at 2 rows, Gemma tg64
  38.7 to 37.0. Three shader rewrites failed; the lever is the compiler's scheduling (agxperf's post-RA scheduler
  does not move these loads up).
- 31 Oct, VERIFIED (test-only edits restored after): the stock q4_K matrix-vector shader at 2 rows,
  4096x14336, takes 102 us; with its arithmetic replaced by one xor and add (every load kept) 77, with A's loads alone
  64, against a 55 us read of the same 33 MB: arithmetic ~25 us, B ~14, A's pattern ~9. Loading B and its sums once
  for all rows (one column; the min term 4 fma instead of 16) passes MUL_MAT and MUL_MAT_ID and is slower: 100 to
  121 us at 1 row, 101 to 117 at 2, Gemma tg64 38.7 to 36.4, GPT-OSS 120B 49.0 to 46.5. As with the matmul, fewer
  instructions do not mean faster under this compiler (INFERRED: its scheduling of loads against their uses).
- 31 Oct, VERIFIED: generation. Llama 2 Q4_0 tg64 67.9 t/s (Metal 120). Matrix-vector n=1 against
  Metal (macOS results 20261028-022802), us: q4_K 4096x4096 40 / 17.4, 4096x14336 100 / 53, q6_K 4096x14336 114 / 63, f16
  249 / 143, q4_0 69 / 37 (0005). One dependent launch reading 9.4 MB takes 19.4 us here, 33 MB 54.7, 117 MB 191
  (vk-chain read, chain): the shaders run at about twice that floor. Back-to-back launches re-reading 9.4 MB reach
  2700 GB/s, so the system cache serves the GPU under Linux too. Kernel_mul_mv_q4_K_f32's layout ported to
  mul_mat_vec_simd.comp (tests pass) is no faster than the stock q4_K shader: 16-bit loads 25-30 % slower, 32-bit
  loads even at 2-4 rows. Small ops run 2.4-2.6x Metal (ADD of 4096 floats 8.2 against 3.8 us, ROPE 2.4x): a fixed
  per-dispatch cost.
- 30 Oct, VERIFIED (Metal from macOS results 20261028-005632; head sizes from the GGUF metadata):
  FLASH_ATTN_EXT against Metal by head size, geometric mean over test-backend-ops' cases: 64 (GPT-OSS) prompts 1.95x,
  generation 2.96x; 128 (Llama 2) 2.05x / 2.65x; 256 (Qwen, Gemma's sliding layers) 2.32x / 2.18x (q8_0 caches
  0.90x: Vulkan ahead); 512 (Gemma's global layers) 8.54x / 3.32x; 576/512 (no model here) 10.1x. With f32
  accumulation a 512 head needs ~34 KB of shared memory at 4 subgroups, past Honeykrisp's 32 KB, so prompts took the
  scalar shader. Patch 0014 drops to 2 subgroups then: hsk 512 at 16k-32k keys 20-30 % faster, 4k even; FLASH_ATTN_EXT
  5368/5368 pass; Gemma pp4096 921 to 941 at depth 0, 228 to 237 at depth 16k, generation even (it keeps the scalar
  path at one token). The 512 head stays ~6x behind Metal.
- 30 Oct, VERIFIED (my build of the series with 0013; MUL_MAT_ID 1109/1109): against Metal's
  MUL_MAT_ID (macOS results 20261028-022802) the worst cases were 32-64 tokens over 32 experts (q8_0 6.6x, iq4_xs 8.7x):
  `GGML_VK_MMV_ID_MAX=64` kept them on the matrix-vector path, which reloads an expert's weights per token. It wins at
  2 tokens an expert (q4_0 e128 u8 n32: 628 against 1128 us), is even at 4, loses at 8 (q4_0 e32 u4 n64: 1343 against
  793). Patch 0013, `GGML_VK_MMV_ID_PER_EXPERT=2`: llama-bench batches of 9 / 16 / 24 / 32 / 48 / 64 tokens, Gemma 136
  / 149 / 103 / 124 / 155 / 178 to 136 / 149 / 103 / 124 / 184 / 239, GPT-OSS 20B 148 / 160 / 115 / 133 / 157 / 173
  to 147 / 161 / 119 / 154 / 214 / 279; Qwen (512 experts) and GPT-OSS 120B (128 of 4) even. 3 an expert is worse
  on Gemma's 48. `llama-run.sh` and `llama-compare.sh` set 2. The other MUL_MAT_ID cases are 2-4x Metal, as the
  dense matmuls.
- 30 Oct, VERIFIED (test-only edit restored after; MUL_MAT 2275/2275): fetching the next k block of
  B (llama.cpp's aligned 8-wide loads) into registers before this block's matrix ops, stored to shared memory at the
  next block, is slower: 512 threads 128x128 f16 6340 to 8994 us, q4_0 5226 to 7034; 256 threads 128x64 f16 +7 %,
  the rest even. With double buffering also failing, overlapping the loads from the shader side does not
  pay under this compiler (INFERRED: the held registers cost more than the hidden latency).
- 30 Oct, VERIFIED (test-only edit restored after; MUL_MAT 2275/2275): two shared tiles in turn in
  mul_mm.comp's coopmat path (the next k block loaded before this one's matrix ops, one barrier a block, no row
  padding) overlap little. 256 threads 128x64: q4_0 6433 to 6002 us, q8_0 7292 to 6887, q4_K 7855 to 7673, f16 7833
  to 8067; 512 threads 128x128: f16 6340 to 8160, q4_0 5215 to 6105. Neither beats the single-buffered 512-thread
  tile `llama-run.sh` uses. Each thread still waits for its own global loads before its matrix ops; overlap would
  need the loads held in registers across the multiply (a loader split into fetch and store, per weight type).
- 30 Oct, VERIFIED (test-only edit restored after): at 16x16x16 the matmul loop without global loads takes
  3896 us (15.4 TFLOPS; the 11.7 above was 8x8x8), and its two barriers cost 0-2 %. That is about what `vk-chain.sh mma`
  gets from a single launch of 128 workgroups (16.8), and 4096x14336x512 on the 128x128 tile is 128 workgroups: the
  loop is near the hardware for its grid. The full kernel (q4_0 5220 us) is that loop plus ~1300 us of global loads
  that do not overlap it (INFERRED: llama.cpp's mul_mm loads a tile, waits at a barrier, then computes; Metal's 1024
  small threadgroups overlap loads of some with compute of others).
- 30 Oct, VERIFIED (`vk-chain.sh mma`, agxperf): the matrix hardware itself is fast under Honeykrisp.
  From registers 23.0 TFLOPS at 8x8x8 and 26.5 at 16x16x16 (of ~27); loading 2 A and 2 B tiles from shared memory
  per 4 ops, llama.cpp's ratio, 15.7 and 21.3 (B row-major 17.4 and 23.8); a barrier every 2 steps or llama.cpp's
  padded rows change nothing. One launch alone needs many workgroups: 76 groups of 256 threads 10.0 TFLOPS, 128 16.8,
  304 16.5, 1216 19.9. So llama.cpp's matmul loop at 11.7 TFLOPS (no global loads) runs at about half of what the
  same op mix gets here; split-k through `GGML_VK_SHADER_CORES` (304-1216: 128 tiles split 2-8 ways) gains 0-4 %.
- 30 Oct, VERIFIED (shaderdb): occupancy is not the bound either. The matmul shader at 8x8x8 has 87
  registers, at 16x16x16 103, both 1024 threads; 64x32 per warp at 16x16x16 (256 threads) has 143 registers and 704
  threads and is the fastest 4096x14336x512 (f16 5702, q4_0 5077 us), yet slower on every prompt than the 512-thread
  tile `llama-run.sh` keeps (Llama 2 832 / 932 / 917 against 875 / 949 / 937, Gemma 834 / 960 / 899 against 858 /
  1008 / 955): the one-shape operator test misleads for prompts.
- 30 Oct, VERIFIED (test-only edit restored after): Mesa keeps the coopmat k-step loop rolled (`while r31 <
  32`); unrolled by hand in mul_mm.comp, 16x16x16 runs 7.8 instructions a matrix op for the whole k loop with its
  loader (about 11 before) and is slower: f16 6400 to 7905 us, q4_0 5250 to 5768; at 8x8x8 the unrolled form spills
  into 400 csel and doubles the time. Tests pass. With fewer moves and fewer instructions both
  failing, the loop's bound is not issue (INFERRED): latency or occupancy, next to read in shaderdb's registers and
  threads per variant.
- 30 Oct, VERIFIED (test-only switches in my builds, restored after), what does not move the
  512-token matmul at 16x16x16 (f16 / q4_0 / q8_0 / q4_K ~6400 / 5250 / 5450 / 7100 us): (1) fewer moves: the loop's
  accumulators are scalar 16-bit phis that land on misaligned half-registers (r26h:r27l), so each matrix op gathers
  its accumulator with two moves and the loop ends in a ~30-move parallel copy; a Mesa pass packing 16-bit vec2 phis
  into 32-bit ones before scalarizing (my driver build in `_tmp/claude-mesa`, agxperf) cuts the moves 90 to 73 (8x8x8:
  73 to 57), tests pass, and the times stay or worsen (16x16x16 f16 6424 to 7926): the loop is not issue-bound by its
  moves; (2) f32 accumulators (Metal's form): 13-50 % slower; (3) shared-memory row padding 0-12: even, except q4_K at
  padding 0, 7100 to 5850 us (-18 %, three rounds), which moves prompts little (Gemma 858 / 1005 / 952 to 876 / 994 /
  917, GPT-OSS 120B 526 / 709 / 857 to 568 / 750 / 861) because the padding applies to every type.
- 30 Oct, VERIFIED (Mesa's `AGX_MESA_DEBUG=shaders`, f16 matmul; 212-266 instructions undecoded by Mesa's
  disassembler, so counts are lower bounds): at 16x16x16 the matrix loop runs 224 instructions for 32 matrix ops, 7.0
  per op (8x8x8: 144 for 16, 9.0): 90 mov, 55 iadd, 24 local loads. Local loads per op now 0.75, Metal's figure; moves
  2.8 per op against Metal's ~0.1 are what is left in the loop.
- 30 Oct, VERIFIED (my build with 0012): where a 512-token matmul's time goes, by removing parts
  of mul_mm.comp (timings only): without any global load every type takes ~5120 us (11.7 TFLOPS), so the shared-memory
  matrix loop alone caps it; without the matrix ops q4_0 takes 1620 us, f16 4110. Honeykrisp's first coopmat shape is
  8x8x8 (INFERRED: the default times equal `GGML_VK_COOPMAT_SIZE=8`'s in a test build), which llama.cpp takes; 0001's
  warptile fields pick 16x16x16 without a patch (`GGML_VK_WT_M=512,128,128,,32,32,,16,16,16`). 4096x14336x512: f16
  6879 to 6324 us, q4_0 6267 to 5220, q4_K 6771 to 7062; MUL_MAT 2275/2275 and MUL_MAT_ID 1109/1109 pass. Prompts
  (pp512 / pp2048 / pp4096), 8x8x8 to the medium tile at 16x16x16 with the small expert tile kept at 8x8x8 (16 there
  costs short MoE prompts 4-14 %): Llama 2 734 / 807 / 807 to 875 / 949 / 937, Qwen 565 / 722 / 753 to 587 / 749 /
  806, Gemma 817 / 923 / 867 to 858 / 1008 / 955, GPT-OSS 120B 523 / 703 / 798 to 527 / 711 / 858. `llama-run.sh`
  takes it. Metal's own tile shape (64x32 at 128 threads) is 15-40 % slower here.
- 30 Oct, VERIFIED (my build of the series with 0012; 0011's numbers as in the medium-tile entry above): the coopmat
  loop reloaded every B tile for each A tile; patch 0012 keeps a k step's B tiles in registers. f16 4096x14336x512
  8020 to 7060 us (7.5 to 8.5 TFLOPS), q4_0 and q8_0 unchanged (their time is in the loader's dequantization),
  MUL_MAT and MUL_MAT_ID tests pass. Prompts (pp512 / pp2048 / pp4096, 512,128,128): Qwen 551 / 714 / 744 to 565 / 722
  / 753, Gemma 805 / 909 / 885 to 817 / 923 / 867, GPT-OSS 120B 505 / 687 / 758 to 523 / 703 / 798, Llama 2 (q4_0)
  even. `GGML_VK_DISABLE_INTEGER_DOT_PRODUCT=1` changes no type: every quantized matmul here already runs the
  coopmat loop (9-10 TFLOPS), so their gap to Metal is the loader. Honeykrisp has `VK_EXT_pipeline_robustness`.
- 30 Oct, VERIFIED counts, INFERRED kernel names (dougallj/applegpu 28dd804 on the shader cache of macOS results
  20261028-025320, Mesa's final code from `AGX_MESA_DEBUG=shaders` (the entry below); innermost loop = the range of its backward branch): Metal's
  `kernel_mul_mm` family, the loops with 32 `simd_matrix_fmadd32`, 24 threadgroup loads, ~17 threadgroup stores and
  2 barriers (llama.cpp's 4x2 8x8 fragments per simdgroup over a 32-wide k step), runs 142-280 instructions per
  iteration, 4.4-8.8 per matrix op, with the next tile's device loads and dequantization inside and 4 movs in most
  variants. Mesa's coopmat inner loop runs 167 instructions for 16 `simd_matrix_fmadd16`, 10.4 per matrix op without
  its device loads: 72 mov, 36 local loads, 28 iadd. Per matrix op: local loads 0.75 against 2.25, moves ~0.1 against
  4.5. Apple loads each fragment once into the registers the matrix op reads and reuses it; Mesa's lowering loads
  more and copies everything into place (the moves turned out not to bound the loop: the fewer-moves entry above). Metal's
  flash attention: 128 matrix ops in 601-678 instructions.
- 30 Oct, VERIFIED (`AGX_MESA_DEBUG=shaderdb` and `shaders`): the matmul shader has 93-97 registers,
  1024 threads, no spills; its inner loop issues 16 `simd_matrix_fmadd16` among ~190 instructions (36 local loads,
  ~90 mov/collect/split to assemble the operands, 28 iadd; 167 in the final code, below), and its loader 128 `icmpsel` (bounds clamps) for 32
  device loads. Larger per-warp tiles that reuse operands more: 64x32 per warp (`256,128,128,,64,32`) f16 -23 % in
  test-backend-ops, q8_0 -2 %, and nothing on real prompts (Llama 2 744 / 809 / 809 to 739 / 802 / 791); WMITER 4 is
  fast but wrong. The lever left is the operand assembly the compiler emits, a Mesa matter (superseded, 30-31 Oct:
  16x16x16 matrices gained 18 %, moves and instruction counts were not the bound, the global loads are; above).

### What moved Honeykrisp forward

- One 4096x14336 matrix-vector (test-backend-ops perf, µs), Metal / MoltenVK / Honeykrisp: f16 143 / 161 / 247; q4_0
  37 / 100 / 81, 68 with the Metal-layout shader (`GGML_VK_MMV_SIMD=1`, 0005, 8 rows a workgroup); q8_0 57.5 / 90 /
  160, 126-128 with that shader or 4 rows. Generation with the shader: Llama 2 65.1 to 69.7, Qwen 33.6 to 34.8,
  GPT-OSS 70.2 to 70.9 t/s.
- Prompts: the medium matmul tile at 256 threads, 128x64 (`GGML_VK_WT_M`, 0001), +12-23 % (Qwen pp2048 672 to 780).
- Batches of 9-64 tokens: the matrix-vector path stopped at 8 columns, so 9 tokens ran 4x slower than 8; raising the
  limit to 64 for MoE layers and 16 for dense ones (0002, 0003) takes a 9-token Qwen batch from 37 to 107 t/s, and
  speculation with ngram-mod drafts of up to 128 tokens a Qwen code edit from 30 to 55-59 t/s, same text. MTP heads
  speed Gemma and Flash-Next up but change the text. 0002 also keeps offset expert-id views off the matrix-vector
  path, which aborted (`allow_misalign || misalign_bytes == 0`).
- Rows per workgroup: 4 for Qwen, 2 for Gemma, 1 for GPT-OSS and dense models with the shader on; the integer-dot
  path is slower.
- Driver: agxperf (coopmat Mesa plus a third-party compiler series) with bit 47 on local loads only (on stores it
  breaks ARGMAX) and clustering off: prompts +17 %, generation +1-3 %, all 21303 operator tests pass.
- Benchmarks take `~/.cache/linux-lab-gpu.lock` (flock): two runs sharing the GPU halve each other.

### GPU usage per client

- VERIFIED, 29 Oct: every GPU client has `drm-driver: asahi`, `drm-engine-render/compute` and
  `drm-total/shared-memory` fdinfo lines on the new kernel, memory correct, busy time 0 ns even for a client
  saturating the GPU. The Rust DRM abstraction had lacked a `show_fdinfo` hook and the GEM file operations did not set
  it (`src-patches/linux/asahi-fdinfo` 0001-0002). The firmware stamps a command's start and end only when its
  microsequence carries Timestamp ops, which the driver adds only for user timestamp queries; 0003 adds them for every
  command behind `asahi.busy_stats=1` (built, waits for the next reboot). KDE's GPU sensor only enumerates PCI GPUs,
  so it needs a backend for platform GPUs reading these lines (read in ksystemstats).

### Metal and Honeykrisp in detail

Metal: macOS 15.8.1, llama.cpp 2280f0f, 27-28 Oct, VERIFIED (`results/macos/macos-15`, runs `20261027-234455` to
`20261028-025200`; each figure the median of 3-5 runs, which agree within 2 %). Flash attention on, all layers on the
GPU, batch 2048.

Model files: Llama 2 3.6 GiB, GPT-OSS 20B 12.3, GPT-OSS 120B 58.7, Gemma 4 15.8, Qwen3-Coder-Next 80.4. Linux:
`var/compare-20261029-133010` (Llama 2 at 1 row from `compare-20261029-132759`).

Tokens per second against batch size, Metal / Honeykrisp (llama-bench, one prompt of N tokens: the speed a speculative
step pays to verify N tokens):

| N | 1 | 2 | 4 | 8 | 9 | 16 | 24 | 32 | 64 | 128 | 512 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Llama 2 | 119 / 71 | 179 / 96 | 352 / 145 | 680 / 171 | 529 / 167 | 906 / 153 | 631 / 112 | 836 / 149 | 1116 / 298 | 1326 / 493 | 1518 / 764 |
| GPT-OSS 20B | 118 / 73 | 182 / 92 | 268 / 122 | 333 / 150 | 348 / 150 | 388 / 163 | 386 / 110 | 514 / 127 | 860 / 166 | 1219 / 350 | 1947 / 821 |
| GPT-OSS 120B | 88 / 51 | 128 / 64 | 181 / 85 | 223 / 103 | 234 / 104 | 259 / 111 | 251 / 72 | 248 / 83 | 410 / 108 | 543 / 162 | 998 / 389 |
| Gemma 4 | 91 / 41 | 146 / 66 | 231 / 102 | 334 / 135 | 328 / 137 | 414 / 149 | 370 / 99 | 548 / 119 | 884 / 175 | 1355 / 342 | 2099 / 712 |
| Qwen3-Coder-Next | 64 / 36 | 101 / 53 | 149 / 80 | 206 / 100 | 204 / 96 | 242 / 98 | 214 / 84 | 377 / 102 | 626 / 156 | 932 / 210 | 1536 / 446 |

Both dip at 24 tokens. The gap widens from about 2x at one token to 4-5x at 64, where Metal keeps climbing and
Honeykrisp's matrix-vector path has stopped paying: verification batches are where Metal pulls furthest ahead.
Llama 2 at 4 rows a workgroup instead of 1 drops to 24-76 t/s at 2-16 tokens: dense models stay at 1 row.

Speculative decoding through llama-server (`macos/spec-req.py`: rename a variable in `gpu/llama-run.sh`, greedy, 1500
tokens), t/s, Metal / Honeykrisp:

| model | none | ngram-mod 64 | ngram-mod 128 | MTP head |
|---|---|---|---|---|
| Llama 2 | 90.4 / 24.7 | 383 / 132 | 405 / 155 | - |
| GPT-OSS 20B | 108 / 52.0 | 279 / 66.1 | 304 / 69.2 | - |
| GPT-OSS 120B | 79.9 / 36.6 | 142 / 43.3 | 151 / 45.1 | - |
| Gemma 4 | 69.3 / 20.2 | 68.6 / 19.2 | 65.0 / 19.1 | 115 / 32.2 |
| Qwen3-Coder-Next | 59.5 / 30.1 | 204 / 55.7 | 216 / 70.2 | - |

The script being edited changed between the macOS and the Linux runs, so the texts differ (same request, similar
length); within a run every setting gives the same text except on Gemma and GPT-OSS, whose batched verification rounds
differently (INFERRED). Flash-Next (Linux only): 17.7 none, 37.2 / 48.3 ngram-mod, 29.5 MTP.

What Metal's graph work is worth (tg128 and pp512 with each optimisation switched off, against the default):

| model | fusion off | concurrency off | reordering off | all off |
|---|---|---|---|---|
| Llama 2 | 0 % / 0 % | -4 % / -4 % | 0 % / -1 % | -5 % / -4 % |
| GPT-OSS 20B | -6 % / -1 % | -8 % / -3 % | -8 % / -3 % | -13 % / -3 % |
| GPT-OSS 120B | -7 % / -1 % | -10 % / -2 % | -10 % / -2 % | -16 % / -3 % |
| Gemma 4 | -25 % / -4 % | -14 % / -2 % | -10 % / -4 % | -28 % / -6 % |
| Qwen3-Coder-Next | -22 % / -3 % | -12 % / -5 % | -9 % / -3 % | -28 % / -8 % |

One op at a time (test-backend-ops perf, µs): matrix-vector 4096x14336 f16 143, q4_0 37.0, q8_0 57.5, q4_K 53.5,
q6_K 63.4; 14336x4096 q4_K 45.8; the smallest op (ADD of 4096 floats) 3.8; GATED_DELTA_NET for one token 8.6. A
dependent Metal launch costs 2.27 µs (metal-chain), 0.30 when independent. Power: the GPU at 1398 MHz throughout,
~113 W on Llama 2 prompts, Qwen ~94 W on prompts and ~44 W generating.

The same build's Vulkan backend through MoltenVK 1.4.2: Llama 2 788 / 836 / 59.9, GPT-OSS 20B 992 / 1221 / 82.7,
Qwen3-Coder-Next 422 / 574 / 24.8 (pp512 / pp2048 / tg128).

## Power management (PMP)

State on 4 Nov, for anyone picking this up (the entries below are the evidence, newest first):
- What it is: the M2 Ultra's power management processor sets memory (DCS) and fabric (FAB, AFR) performance states
  from device requests in its report region. Stock Asahi does not start it on this chip (its `APPLE_USE_PMP` tree
  does not compile for t6022, and the stock tree has no pmp alias), so on Linux the memory and fabric stay in one
  fixed state.
- What runs it here, by hand after each boot: the `t6022-pmp` tree (`TBT_OVERLAYS="t6022-ane t6022-pmp"
  kernel/tbt-kernel.sh dtb`, reboot), then `kernel/pmp.sh build`, `votes`, `start --now`. It runs until reboot. Not
  yet at boot: that is a board line (the kernel series carries the fixes, the tree becomes the default).
- What it gives (one run each, same method, macOS in brackets): idle 21.32 -> 16.08 W (16.2-16.7); GPU read 1 GB 668
  -> 775 GB/s (755-763), 16 MB 998 -> 1818 (1909), one float4 a thread 296 -> 468 (762); llama.cpp generation +14-20%,
  prompts +1-5%.
- What we fixed against Asahi's code, each usable on its own: (1) the request word: start with macOS's
  0x0001e6006000c700 (Linux's tree has no report entry for the P-CPU clusters or the GPU, and pmp-report shifts a
  32-bit 1, so no bit past 31); (2) pmp.rs numbers AdvertiseAcks from 1 and spends an index on a missing property,
  macOS from 0 and spends none, and pmp.rs's SetVal then reads past its list; (3) any second mapping of the report
  must be non-posted (`ioremap_np`), or the first write hangs the machine; (4) `APPLE_USE_PMP` on t6022: an undefined
  die-1 label, die 1's DCPs on die 0's DISPEXT2/3 entries; (5) m1n1's 96 KB tree margin is short with the PMP's
  settings (`tbt-kernel.sh` pads 64 KB).
- Open, in order of weight: does the start hold without macOS's word (untested); what bits 41, 42 and 45-48 mean (no
  device table names them); die 1's word 1 (macOS wrote none; HDMI stayed fine without it, OBSERVED once); the
  tunables' values (names and sizes match macOS, values not compared); nine more report registers macOS writes and
  Linux does not; energy under load (one SMC snapshot each at the start of the Qwen run: 144.7 W off, 175.6 W on,
  +21%, against +5% prompt and +20% generation speed, so energy per token is not shown to improve and may be worse
  for prompts; not measured over a run); whether the tree still hangs under load with the PMP stopped (moot once it
  starts at boot).

- 4 Nov, VERIFIED (`results/linux/pmp-20261104`, `kernel/pmp.sh measure`, the same method both runs; quiet, 300 s of
  SMC Total System Power, then vk-chain bw): the PMP runs under Linux (t6022-pmp tree; `pmp.sh votes` with macOS's word
  0, then `start --now`: status bit 0 set, word 0 acknowledged bit for bit at 0x0001e6006000c700, firmware "PMP
  started", kernel log clean) and closes most of the gap to macOS. PMP off (old tree, 01:12) -> on (07:05), macOS:
  idle 21.32 -> 16.08 W (16.2-16.7); GPU read 1 GB 668 -> 775 GB/s (755-763); 16 MB 998 -> 1818 (1909); one float4 a
  thread 296 -> 468 (762). Without the PMP the memory and fabric sit in one middle state; with it they rise under GPU
  load and drop at idle. Left: the one-float4 pattern (61% of Metal), a GPU-stack question.
- 4 Nov, VERIFIED (`results/linux/pmp-20261104/pmp-on-bench` against `pmp-off`, llama-compare's bench, same models,
  build and agxperf driver): with the PMP running, generation gains 14-20% and prompt processing 1-5%. tg128: llama2
  71.2 -> 81.4 t/s (Metal 123.5), qwen 36.9 -> 44.4, gpt20 74.0 -> 84.5. pp512: llama2 876 -> 896 (Metal 1516), qwen
  741 -> 779, gpt20 1053 -> 1109; pp2048 within 1-4%. So llama2 generation is at 66% of Metal (57% before) and prompt
  processing still at 59%: the rest of the gap is in the GPU stack. The t6022-pmp tree also held the bandwidth run and
  this bench with the PMP running, the load that hung it twice with the PMP stopped (3 Nov).
- 4 Nov, VERIFIED (five hangs, then one write that held): every `votes` hang (twice 3 Nov, three times 4 Nov, whatever
  the bits) was pmp_votes writing the report through plain `ioremap` on a `nonposted-mmio` bus: posted writes hang the
  machine, reads pass. With `ioremap_np` the same write held at once (06:48). Map any second view of an Apple SoC
  register non-posted (`of_iomap`, or `ioremap_np` when the resource has IORESOURCE_MEM_NONPOSTED). pmp-report itself
  writes the word non-posted at every boot: its always-on entries (DISPEXT0/1, AFNC4/5_IOA) set 0x6000c000 when they
  probe, and genpd then lists them `off-0`, because pmp-report registers them as off after setting the bit
  (VERIFIED, pmp-report.c and the running tree, 4 Nov; corrected: this line said that value was iBoot's and that
  Linux had never written the word). The PMS, PMS-SRAM, bridge, c1ppt and PMP domains were on, on both dies.
- 4 Nov, VERIFIED (m1n1 hypervisor trace of macOS 13.7.8 booting, `macos/hv-pmp.sh`; raw log kept off-repo, on the
  operator's stick and in-session): macOS's PMP bring-up uses the exact message protocol our `drivers/soc/apple/pmp.rs`
  implements. Sequence: SetBuf, `GetIOVATable -> IOVA=0x0` (twice; so t602x needs no address table, as our empty-table
  path does), ~794 Advertise/AdvertiseAck (the firmware reads its tunables by name from the ADT), `SetAPPower STATE=0x20`,
  StartEP 0x20. The controller then ran stably for ~28k more log lines; the late crash (a forwarded mailbox write to
  0x28ec08800 faulting, then the USB link dropping) was long after bring-up and is the Mac-side going down under an
  unsupported 13.7.8 guest, not a bring-up problem. So Linux CAN bring the PMP up: the firmware speaks the protocol we
  have. (The 3 Nov start hangs were the lab module's posted writes; see above.)
- 4 Nov, VERIFIED (same trace, PMPRegTracer decode of DEV_STATUS_TGT_WR at report+0x11000): the device-request word is a
  live control loop, rewritten 41 times during boot as subsystems power up and down (not a one-shot), exactly what
  `pmp-report`'s genpd does per power domain. Bit = soc-device id1 - 1, confirmed: GFX = bit 10 (macOS sets and holds it
  -- the bit linux-aurora PR 334 proposed), PCPM0/1 = 8/9, DISPEXT0/1_FE = 14/15, AFNC4/5_IOA = 29/30. Steady state this
  boot 0x61e6006000c700 (GFX, both display FEs, the two P-CPU clusters, the two fabric IOAs, and bits 41-54 that no
  soc-device or pmgr entry names: the tracer's "DPn-SOC-VMAX" for them is its own misdecode, those share bits 14/15).
  All writes were word 0 (bits <64); no word-1 writes occurred (no die-1 display attached this boot), so pmp_votes'
  word-1 path stays unconfirmed. macOS set no DCAP-dependent behaviour visible here; DCAP left 0 matches its M2 init.
- 4 Nov, VERIFIED (static diff of that trace against the ADT, the tree m1n1 fills and our driver; nothing run): what
  Linux does differently when it starts the PMP, most likely cause first.
  - Votes. When macOS sets CPU_CONTROL RUN, word 0 holds 0x0001e6006000c700; Linux's holds 0x6000c000 (the two display
    FEs, AFNC4/5_IOA; pmp_votes' dump, 3 Nov). Missing: PCPM0/1 (bits 8, 9: the P-CPU clusters), GFX (10), and bits 41,
    42, 45-48, which macOS sets one each right after its device votes. Linux's tree has no report entry for PCPM or GFX,
    and pmp-report cannot set a bit past 31. `pmp_votes macos=1` sets macOS's word 0 before the start; the start with
    it held (above). Whether the start also holds without these bits is untested.
  - AdvertiseAck numbering. macOS numbers from 0 and answers a name it lacks with INDEX 0 SIZE 0 without spending an
    index; pmp.rs numbers from 1, spends one per miss, and its SetVal looks up entry INDEX of a list that starts at 0
    (the last entry is out of range). The firmware sent no SetVal that boot. `make_lab.py` now numbers as macOS does.
  - Settings: no gap. Of the 794 Advertises, 714 register IOReport channels (size given, nothing looked up) and 80
    look up a tunable by name; 79 of those are in iop-pmp-nub at the size macOS answered, m1n1 copies all 79 (none is
    in its excluded list), and the 80th, `fast-die-ctrl-ce-map`, is in no ADT node and unanswered by macOS too.
    Values were not compared (the trace does not dump the value buffer).
  - Other report writes. macOS writes nine more report registers that Linux never touches: before RUN 0x28e3d8538 =
    0xd00, 0x28e3d824c = 0x40000, 0x28e3d1480 = 0x2111100000000 and 0x28e3d1488-14a0 = 0; after it 0x28e3d1280
    (0x100000000, then 0), 0x28e3d12c0 = 2, 0x28e3d12c8 = 0, 0x28e3d1618 = 6. Their ptd-range names are not mapped.

- 3 Nov, OBSERVED: the `t6022-pmp` device tree (`kernel/dt/t6022-pmp.dts`: the pmp alias, so m1n1 fills the node and
  it goes okay with no driver bound) hard-hung the machine twice, each time in `kernel/pmp.sh measure` (vk-chain bw,
  then llama-compare's bench): once a minute into Qwen, once at the start of GPT-OSS 20B. No kernel message before the
  reset; the PMP was never started (no votes, no `pmp_lab`). (4 Nov: with the PMP running, the tree held the same
  bandwidth run and bench once; with it stopped, still unexplained.) The same bench without the bandwidth run passed
  once on that tree, and the old tree ran bandwidth plus bench that morning. Suspects, untested: the node keeps the
  PMP's power island on ("sync_state() pending due to 28e700000.pmp", where the old tree let it go off with its DART),
  and the node joins its DART's IOMMU group. Use the tree only with the PMP started right after boot.
- 3 Nov, VERIFIED (300 s, load 0.19, qBittorrent stopped): Linux idles at 20.4 W PSTR (`Total System Power`), 10.6 W
  PMVR (`3.8 V Rail Power` in Linux's hwmon); macOS's 8.5 W PMVR and 32.4 W PSTR (28 Oct) were taken mid-collection,
  not idle. GPU read bandwidth that boot: 656-670 GB/s at 1 GB.
- 3 Nov, VERIFIED (ADT dump of 28 Oct, the report region read under Linux): the PMP report's SOC-DEV-PS-REQ is 8 words
  (read 16 bytes a word from 0x2000, write 8 from 0x11000); a device's bit is its soc-device ID - 1, and die 1's
  devices have die 0's IDs + 64 (AVD1 82, DISPEXT4 79 = the HDMI port), so die 1 votes in word 1. Linux's
  `pmp-report` drives word 0 only, with `1 << id` (a 32-bit shift, wrong from ID 31 up; Asahi 414e55d alike).
  Asahi's APPLE_USE_PMP does not compile for t6022 (pmp_report_avd_sys_die1 undefined) and puts die 1's DCPs on
  report@1f/@20, which are die 0's DISPEXT2/3 and stay disabled. m1n1 adds ~95 KB to this board's tree (the kernel
  got 384,726 bytes) within a 96 KB margin, and the PMP's settings are ~27 KB more: `tbt-kernel.sh` pads the tree by
  64 KB with `t6022-pmp`. Of the PMP's 41 boot arguments, BDID, DVID and DCAP are 0 until the OS sets them (the ADT
  has 0x0a, 6 and 8; 8 x 24 GB = this Mac's 192 GB). Without a driver the PMP's status word is 0: not running.

## macOS reference data

- 4 Nov, VERIFIED (`results/macos/macos-13`, `macos-15`; `collect.sh idle dvfs gpu`, llama-bench by hand): macOS vs
  this Linux (7.1.13-tbtwip), same machine. Idle PSTR 16.2-16.7 W / PMVR 8.1-8.3 W, Linux 21.3 W / 10.9 W (+28%): at
  idle macOS holds memory (DCS) and fabric (FAB/AFR) at their lowest state 99.8% of the time, ~1.9 W, 0.45 GB/s; Linux
  cannot be that low (its 668 GB/s needs a high memory state), so it holds memory/fabric near the top state always ->
  the idle gap. Under Metal llama both are driven to top (F5/VMAX) by the GPU's own votes, GPU at P8 = 1398 MHz. GPU
  read bw (vk-chain pattern): 1 GB 755-763 vs Linux 668; 16 MB (in cache) 1909-1926 vs 1005; one-float4-per-thread
  296 vs 762. Metal Llama-2-7B Q4_0 (a91eab67d): pp512 1516 vs 874 (58%), pp2048 1459 vs 950 (65%), tg128 123.5 vs 70.4
  (57%). tg128 123.5 t/s = ~472 GB/s of weights, far under our own 668 GB/s bw -> generation is NOT memory-bound; it
  and the one-float4 gap are many-small-workgroup launch cost + GPU clock (1236 not 1398), fixable in the Linux GPU
  stack. Prompt is compute-bound (30 GB/s DRAM at 113 W). So: idle power + cache-side bw -> PMP; pp/tg speed -> GPU stack.
  Corrected 4 Nov by the PMP run (Power management): Linux's memory and fabric sat in one fixed state, not near the
  top (the 1 GB read rose 668 -> 775 GB/s once the PMP ran them), and generation gained 14-20% from the PMP alone, so
  it was partly held back by that state after all (INFERRED: latency or clock, not the amount of bandwidth). What is
  left is the GPU stack: llama2 tg128 at 66% of Metal, pp512 at 59%.


- 27-28 Oct: `macos/collect.sh` runs on macOS 13.7.8, 14.8.9 and 15.8.1, 45 runs in `results/macos/`: device tree and
  IORegistry, Neural Engine nodes and firmware hashes, Thunderbolt and PCIe trees, SMC keys idle and under load,
  llama.cpp on Metal and on MoltenVK, Metal's fusion ablation and per-op timings, Core ML on the Neural Engine, input
  reports. Serial numbers, UUIDs and network addresses are replaced. Not collected: vk-chain on MoltenVK, the
  convolution form of the Neural Engine benchmark.
- 27 Oct: Core ML planned every batch-1 linear on the CPU and only batch 64 on the Neural Engine; Apple's own
  transformer code uses 1x1 convolutions on `(1, C, 1, S)` instead.
- 13 Oct: the m1n1 hypervisor supports macOS 13.5 and 14.8.3 guests only, as a second volume in the macOS container;
  13.5 is also the firmware Linux runs with here.

## Storage server

33 HFS+ disks of 18 TB moved to XFS in place, disk by disk, all in the two M424 boxes now: 32 done, disk 33 (still
HFS+) the last. The pool holds 378 TB (344 TiB) of 504 TB (459 TiB); raw capacity 594 TB (540 TiB). Layout
(`storage/snapraid-setup.sh`): data disks by label at `/mnt/data/NN`, parity at `/mnt/parity/NN`, one mergerfs pool
at `/srv/pool` (create policy `pfrd`, `minfreespace` 900G), SnapRAID with 4 parity levels, content files on the root
and on four data disks.

- 28 Oct: `minfreespace` 900G leaves each 16.4 TB disk 15.5 TB of data; `snapraid-setup.sh need` checks that the
  parity disks hold the fullest one at a given block size, each file rounded up to whole blocks.
- 17 Oct, VERIFIED: a slow USB disk stalled the whole machine (rsync, `sync`, shutdown in state D) through the page
  cache: gigabytes waited unwritten behind a 1-command queue. `settings.sh usb-cap` limits it to 256 MiB per USB disk.
  The backup disk is shingled (SMR, INFERRED), so restic's large sequential packs suit it where rsync ran at 1.5 MB/s.
- 17 Oct: the hfsplus driver cannot decompress: files macOS keeps compressed (`com.apple.decmpfs`) read as empty and
  pass a size-and-time check. `migrate-row.sh` lists and holds them. Names it cannot convert (an emoji) cannot be
  opened at all; those were declared expendable.
- 17 Oct: the quick verify never compares bytes, and the tunnel's DMA path is new code, so 2000 files a disk are read
  back in parts before a source is formatted: 86 % odds of catching a fault in 1 of 1000 files, 99.995 % at 1 in 200.
- 16 Oct, VERIFIED: a global `sync` in one worker waited hours for every other writer; per-file fsync took 5 h for
  466,599 files. One `syncfs` per pool branch waits for those disks only.
- 16 Oct: `rsync --no-inc-recursive` lists the whole tree before copying, days on a slow disk of small files.
- 15-16 Oct, the home-made boxes: SATA faults across boxes stopped when the Mac got a three-pin, earthed cord (its
  chassis floated and the boxes' leakage ran through the USB-C shields; OBSERVED). The rest were one bay's connector
  on one box's controller board, found by swapping disks; spin-down after 1-3 idle minutes made the pool wake disks
  many times an hour.
- 14 Oct: XFS everywhere because a SnapRAID parity file of 16.4 TiB exceeds ext4's 16 TiB file limit.
- 18 Oct: smartd checks every disk each 30 min without waking a sleeping one; KDE's disk monitor runs `smartctl --all`
  without `-n standby` and spins them up.

## Desktop

- 29 Oct, VERIFIED: the TV's profile is now macOS's own (`desktop/icc/lg-tv-macos.icc`, from
  /Library/ColorSync/Profiles/Displays): the TV's EDID primaries, exactly BT.2020's, the sRGB tone curve, an identity
  video-card gamma. Compared by eye it beat the profile used since 18 Oct (oled-tv-calibrator's "Native HDR": fixed
  primaries between sRGB and P3, gamma 2.2, no measurement), which is dropped.
- 18 Oct, VERIFIED: closing a window from the Cmd+Tab switcher dropped other windows from it. Cause: libplasma's
  Dialog sizes the window with its margins truncated and gives the item back the window minus the margins unrounded,
  so Thumbnail Grid loses a column. `ux-fix.sh switcher` sizes the grid by its own columns; the same change is
  prepared for KWin.
- 29 Oct, VERIFIED by feel: input as on macOS 15 (`results/macos/macos-15/20261028-064704`). macOS moves the pointer
  0.875 points per mouse count with acceleration off (43339 for 49012 in mouse-move, its scaling 0.875), so the Magic
  Mouse is flat at -0.125 in KDE; the trackpad flat; key repeat 250 ms then 30/s (hidutil 33.3 ms); natural scrolling
  off; Magic Mouse scroll speed 50. `ux-fix.sh input`, `magicmouse.sh speed`.
- 29 Oct: no upstream code stops a resting finger from scrolling while the mouse moves; `src-patches/linux/hid-magicmouse`
  does (`scroll_hold_ms`, best at 1 ms, one tick at HZ 1000). Built into the kernel, its parameters are set by
  tmpfiles.d: modprobe.d options never reach a built-in driver, and the initramfs lacked them for the module (17 Oct).
- 29 Oct: the trackpad's three-finger tap is a middle click that no setting removes: libinput's tap map only swaps it
  with the two-finger tap, and KWin's `[ButtonRebinds][Mouse]` reads only `ExtraButton1`-`24`
  (`src/plugins/buttonrebinds/buttonrebindsfilter.cpp`). Middle-click paste is off (`ux-fix.sh on`), so a stray tap
  pastes nothing; the driver is where it can go.
- 30 Oct: the wheel changing a hovered slider or combo box has no setting (KDE bug 399324). A Qt style wrapping Breeze
  that passed the wheel on from unfocused controls did not hold in daily use, so it was dropped (commit history).
- 17 Oct: KWin's Minimize All script ("Minimize all other windows", Meta+Shift+O) replaces kwin-solo-window, which
  asks KWin for its whole debug report on every window event.
- 29 Oct: keyboard: layout `us` variant `intl-unicode`, model `applealu_iso`, compose on the right Cmd, Caps Lock as
  Escape (the operator's own; `ux-fix.sh keyboard` has the `gb mac` alternative). Program shortcuts are switched off with
  `_launch=none` in kglobalshortcutsrc.

## System

- 17 Oct, audit (`system/system-audit.sh`): `macsmc-rtc` sets the clock 8 s into boot, so every boot's journal starts
  on the systemd epoch; smartd scanned before the disk boxes were up (`settings.sh smartd-rescan`); a kernel update
  would boot without the disk boxes (`kernel-pin`); updatedb crawled the pool (`indexer`). 30 Oct: the prune had gone
  stale (data disks moved from /mnt/hd to /mnt/data on 28 Oct), so updatedb walked them all; `settings.sh indexer
  status` names any path it no longer prunes.
- 13 Oct: the Asahi installer's resize prompt asks for the new macOS size; GB and TB are decimal. It adds a boot stub,
  a 500 MiB EFI and a 1 GiB `/boot`. Partitions are removed with `diskutil`, never the recovery one.
