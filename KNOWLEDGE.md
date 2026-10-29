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

- 29 Oct: the repository is published with a fresh history; device identifiers may appear, Apple's compiled code
  (the runs' `private/`) stays out.
- 26 Oct: kernel work stays a disclosed branch of the Ophuscado/linux fork; anyone may cherry-pick it; a submission
  follows the target project's rules on tool use (the kernel's coding-assistants.rst asks for transparency and a
  human Signed-off-by; Asahi forbids generative AI for material contributions, so Asahi gets reports only, written
  by hand). Each public repository's README is its showcase; temporary work lives in branches.
- 26 Oct: SnapRAID as one array over every disk, 4 parity disks, 6 at most (SnapRAID's limit).
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
  `kernel/dt/t6022-ane-dart-power.dts` fixes it; prepared for omarchy-ane as
  `src-patches/linux-ane/m2-ultra-dart-power`.
- 29 Oct: dtc 1.7.0's fdtoverlay renumbers a labelled node's phandle and leaves its users dangling (1.7.1+ does not);
  `tbt-kernel.sh` refuses a tree with more unresolved references than before its overlays.

## GPU: llama.cpp on Vulkan against Metal

Same machine, llama.cpp 2280f0f, Honeykrisp (Mesa) on Linux, Metal and MoltenVK on macOS 15. Settings in use:
`gpu/llama-run.sh`.

| tokens/s | Metal pp512 / tg128 | Vulkan on MoltenVK | Honeykrisp, Linux |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1518 / 121.5 | 788 / 59.9 | 762 / 69.7 |
| GPT-OSS 20B | 1945 / 125.0 | 992 / 82.7 | 747 / 70.9 |
| Qwen3-Coder-Next Q8 | 1535 / 67 | 422 / 24.8 | 488 / 34.8 |

- 29 Oct, VERIFIED, one 4096x14336 matrix-vector (test-backend-ops perf, µs): f16 Metal 143, MoltenVK 161, Linux
  247; q4_0 37 / 100 / 81 (68 with `GGML_VK_MMV_SIMD=1`, honeykrisp 0005, at 8 rows a workgroup); q8_0 57.5 / 90 /
  160 (126-128 with either the new shader or 4 rows). Generation with the new shader: Llama 2 65.1 to 69.7 (4 rows),
  Qwen 33.6 to 34.8 (4 rows), GPT-OSS 70.2 to 70.9. Plain f16 streams at 475 GB/s on Linux against 820 on Metal and
  730 through MoltenVK, so part of the gap is below llama.cpp: memory bandwidth reached on Linux (INFERRED; open).
- 28 Oct, VERIFIED: Metal's graph optimisations are worth 7 % of generation on Llama 2, 13-15 % on GPT-OSS, 28-29 % on
  Qwen and Gemma (fusion alone 22-25 %): RMS_NORM+MUL everywhere, the MoE reduce, Gemma's whole router. Prompts move
  3-8 %.
- 28 Oct: MoltenVK runs llama.cpp's Vulkan backend no faster than Honeykrisp, so most of the 2-3x lies in the Vulkan
  shaders and graph, not in Mesa or the kernel (INFERRED).
- 25 Oct, VERIFIED: a launch that waits on the previous one costs 4.0-4.2 µs (Metal 2.27); Qwen issues 1878 launches a
  token, so ~10 of its ~33 ms are fixed launch cost. Without the wait bit in the barrier word, Llama 2 generates
  94.6 t/s (Metal's public 94) but results are wrong: the gap is the serialization of dependent launches.
  `HK_PERFTEST=designedusccdmbarrier` (word 0x17f) is the cheapest correct one: +7-9 % generation.
- 25 Oct: the GPU runs at its full 1398 MHz (one dependent multiply-add 1.57 ns, Metal 1.39); small matrix-vectors are
  latency-bound, not bandwidth-bound.
- 26 Oct, VERIFIED, driver: agxperf (coopmat Mesa plus a third-party compiler series) with bit 47 on local loads only
  (on stores it breaks ARGMAX) and clustering off: prompts +17 %, generation +1-3 %, all 21303 operator tests pass.
- 26 Oct, VERIFIED, prompts: the medium matmul tile at 256 threads and 128x64 (`GGML_VK_WT_M`, honeykrisp 0001):
  +12-23 % (Qwen pp2048 672 to 780).
- 26 Oct, VERIFIED, batches of 9-64 tokens: the matrix-vector path stopped at 8 columns, so a 9-token batch ran 4x
  slower than 8. Raising the limit to 64 for MoE layers and 16 for dense ones (0002, 0003) takes a 9-token Qwen batch
  from 37 to 107 t/s. Speculation with ngram-mod drafts of up to 128 tokens: a Qwen code edit 30 to 55-59 t/s, same
  text. MTP heads speed Gemma and Flash-Next up but change the text.
- 26 Oct: rows per workgroup best at 2 for the MoE models, 1 for GPT-OSS and dense ones; the integer-dot path is
  slower.
- 26 Oct: llama.cpp fails to read a model from the mergerfs pool ("read error: Bad address"); models load from
  `~/Projects/_llm`.
- 28 Oct: GPU usage per client needs `drm-*` fdinfo lines; the Rust DRM abstraction lacked a `show_fdinfo` hook and
  the GEM file operations did not set it (`src-patches/linux/asahi-fdinfo`, in test). KDE's GPU sensor needs a
  ksystemstats backend reading them (INFERRED).
- Benchmarks take `~/.cache/linux-lab-gpu.lock` (flock): two runs sharing the GPU halve each other.

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
HFS+) the last. The pool holds 344 of 459 TB. Layout
(`storage/snapraid-setup.sh`): data disks by label at `/mnt/data/NN`, parity at `/mnt/parity/NN`, one mergerfs pool at
`/srv/pool` (create policy `pfrd`, `minfreespace` 900G), SnapRAID with 4 parity levels, content files on the root and
on four data disks.

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
- 17 Oct: the Magic Mouse settings in modprobe.d did not apply: the driver loads from the initramfs, which lacks the
  file (INFERRED); a tmpfiles.d entry sets them after boot. No upstream code stops a resting finger from scrolling
  while the mouse moves; `src-patches/linux/hid-magicmouse` does.
- 17 Oct: the wheel changing a hovered slider or combo box has no setting (KDE bug 399324); `desktop/qt-nowheel` is a
  Qt style plugin for it.
- 17 Oct: KWin's Minimize All script ("Minimize all other windows", Meta+Shift+O) replaces kwin-solo-window, which
  asks KWin for its whole debug report on every window event.
- 17 Oct: keyboard: `gb` variant `mac`, model `applealu_iso`; ñ through a compose key on the right Cmd. Program
  shortcuts are switched off with `_launch=none` in kglobalshortcutsrc.

## System

- 17 Oct, audit (`system/system-audit.sh`): `macsmc-rtc` sets the clock 8 s into boot, so every boot's journal starts
  on the systemd epoch; smartd scanned before the disk boxes were up (`settings.sh smartd-rescan`); a kernel update
  would boot without the disk boxes (`kernel-pin`); updatedb crawled the pool (`indexer`).
- 13 Oct: the Asahi installer's resize prompt asks for the new macOS size; GB and TB are decimal. It adds a boot stub,
  a 500 MiB EFI and a 1 GiB `/boot`. Partitions are removed with `diskutil`, never the recovery one.
