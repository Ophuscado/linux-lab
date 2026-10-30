# Knowledge

Findings that took work to reach, with dates (2026) and how sure they are: VERIFIED (run or read here), OBSERVED
(seen, not reproduced), INFERRED, UNKNOWN. Newest first in each section. The long notes they were condensed from
(journal excerpts, every bisect step, per-cell tables) are in the repository's first commit, `1b39073`.

- [Decisions](#decisions)
- [USB4 and Thunderbolt storage](#usb4-and-thunderbolt-storage)
- [The Neural Engine](#the-neural-engine)
- [GPU: llama.cpp on Vulkan against Metal](#gpu-llamacpp-on-vulkan-against-metal)
- [macOS reference data](#macos-reference-data)
- [Storage server](#storage-server)
- [Desktop](#desktop)
- [System](#system)

## Decisions

Standing choices, with the reason when one was given.

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
- 29 Oct: dtc 1.7.0's fdtoverlay renumbers a labelled node's phandle and leaves its users dangling (1.7.1+ does not);
  `tbt-kernel.sh` refuses a tree with more unresolved references than before its overlays.

## GPU: llama.cpp on Vulkan against Metal

The same Mac Studio and llama.cpp commit (2280f0f): Metal and Vulkan through MoltenVK on macOS 15.8.1, Vulkan through
Honeykrisp on Linux with the six patches of `src-patches/llama.cpp/honeykrisp` and the settings of `gpu/llama-run.sh`
(Linux measured with `gpu/llama-compare.sh`, the same tests and flags as `macos/collect.sh`). Flash attention on, all
layers on the GPU, the mean of 2-5 runs. More tables under [Metal and Honeykrisp in detail](#metal-and-honeykrisp-in-detail).

| Tokens/s, pp512 / pp2048 / tg128 | Metal | Vulkan via MoltenVK | Vulkan via Honeykrisp |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 1538 / 120.4 | 788 / 836 / 59.9 | 762 / 803 / 68.7 |
| GPT-OSS 20B Q8_0 | 1944 / 2146 / 124.5 | 992 / 1221 / 82.7 | 819 / 1160 / 71.6 |
| GPT-OSS 120B Q4_K | 1001 / 1300 / 94.2 | - | 390 / 656 / 50.1 |
| Gemma 4 26B-A4B Q4_K | 2100 / 2338 / 95.2 | - | 709 / 907 / 39.9 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 1817 / 67.8 | 422 / 574 / 24.8 | 449 / 681 / 34.2 |

### Where the generation gap is

- VERIFIED, 28 Oct: Vulkan through MoltenVK is no faster than Honeykrisp, so most of the 2-3x lies in llama.cpp's
  Vulkan shaders and graph on this GPU, not in Mesa or the kernel (INFERRED from that).
- VERIFIED, 29 Oct: not fusion. A Qwen token is 1805 Vulkan launches against 1996 Metal dispatches (703 of them
  concurrent with the one before); ggml-vulkan fuses as much as ggml-metal, and switching its fusion off drops Qwen
  from 34.6 to 24.7 t/s (+40 % from fusion; Metal's own: +28 %). Metal fuses only RMS_NORM+SCALE (now honeykrisp
  0006: no measurable gain) and GATED_DELTA_NET+CPY (36 a token) beyond it.
- VERIFIED, 25 Oct: the cost of a dependent launch. One that waits on the previous costs 4.0-4.2 µs under Honeykrisp
  (`vk-chain`) against 2.27 on Metal; over a Qwen token the average is ~16 µs a launch on Vulkan and ~7.4 on Metal.
  Without the wait bit in the barrier word Llama 2 generates 94.6 t/s (Metal 120) but results are wrong;
  `HK_PERFTEST=designedusccdmbarrier` (word 0x17f) is the cheapest correct word, +7-9 % generation.
- VERIFIED, 29 Oct: not memory. A grid-stride read reaches 610-655 GB/s from 64 MB to 1 GB (`vk-chain.sh bw`), the same
  on both memory types and both Mesas; one vec4 per invocation (65,536 workgroups for 256 MB) only ~290 GB/s:
  launching many small workgroups is the limit. The f16 matrix-vector streams 475 GB/s, below what memory gives
  (INFERRED: its shape). Metal's matrix-vector figures re-read a 117 MB matrix partly held in the 96 MB system cache,
  an upper bound; Metal's own read bandwidth is not measured yet.
- VERIFIED, 29 Oct: generation over a long context. With the ~4,000-token prompt of the speculation test, Llama 2
  generates 24.7 t/s on Honeykrisp against 68.7 in tg128 (36 %), Metal 90.4 against 120.4 (75 %); Gemma 20.2 against
  69.3 on Metal. Attention over the cache is a second gap beside the launch cost (INFERRED: flash attention with the
  q8_0 cache, not traced yet).
- VERIFIED, 25 Oct: the GPU runs at its full 1398 MHz (one dependent multiply-add 1.57 ns, Metal 1.39).

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
`var/compare-20261029-133010` (run 4697; Llama 2 at 1 row from `compare-20261029-132759`).

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

## macOS reference data

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
  would boot without the disk boxes (`kernel-pin`); updatedb crawled the pool (`indexer`).
- 13 Oct: the Asahi installer's resize prompt asks for the new macOS size; GB and TB are decimal. It adds a boot stub,
  a 500 MiB EFI and a 1 GiB `/boot`. Partitions are removed with `diskutil`, never the recovery one.
