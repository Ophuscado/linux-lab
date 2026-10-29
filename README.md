# linux-lab

A personal lab for improving Linux support on an Apple Mac Studio with M2 Ultra (2023, `j475d`). My machine runs
Fedora Asahi Remix, and this repository is what it takes to make it a complete Linux machine: kernel work for
Thunderbolt/USB4 storage and the Neural Engine, GPU compute for local language models measured against macOS on the
same hardware, a 33-disk storage server, and a desktop close to macOS.

Everything here is tested on that one machine. It is a layer on top of upstream projects (Asahi Linux, Mesa,
llama.cpp, omarchy-ane): changes are kept as patch series against pinned upstream commits, so each can be rebuilt,
published and proposed upstream on its own. The findings, with their evidence and dates, are in `KNOWLEDGE.md`.

## Milestones

Dates are 2026. "First" means the first public report for this chip that a web search on 29 Oct found (an M1 Air
has PCIe over Thunderbolt in another project's kernel notes), not a claim about every lab in the world.

| Date | Milestone |
|---|---|
| 11 Oct | **PCIe over USB4 on the M2 Ultra under Linux: the first public report for this chip.** Asahi's public USB4 series (30 Aug) carries XDomain and USB 3 tunnels and states that PCIe tunnelling is not there yet. Here it works: Apple's tunneled PCIe controller (`apciec`) driven by a ported 2023 driver, its DMA address offset found from macOS's tables, a cable-speed fix, and eight SATA disks per enclosure at 20 Gb/s x2. |
| 11 Oct | **USB4 and the GPU in one kernel.** The USB4 stack backported from Asahi's 7.2 work-in-progress tree (where the GPU driver is marked broken) onto 7.1.13. |
| 22 Oct | **Thunderbolt 3 storage on the same kernel, unchanged:** two 24-bay boxes (Intel Titan Ridge bridge, LSI SAS3008, SAS expander) at 40 Gb/s, carrying 33 disks around the clock with no link or controller error. |
| 29 Oct | **The M2 Ultra's Neural Engine runs under Linux: the first public report for this chip.** omarchy-ane lists M1 and M2 Max as tested (16 Oct); its M2 Ultra overlay panicked the boot. The fix comes from macOS's power tables on this machine (the ANE DARTs sit in the `ANE_SYS` island); firmware boots and the smoke test is 20/20 bit-exact, 0.418 ms. Merged into omarchy-ane the same day (pull request 278), its first T6022 boot report. |
| 25-29 Oct | **llama.cpp on Vulkan, measured against Metal on the same machine and moved forward:** a five-patch series (matrix tiles +12-23 % on prompts; batches of 9-64 tokens 3x faster, which makes speculative decoding pay, 30 -> 55-59 t/s on a code edit; a Metal-style q4_0/q8_0 shader, +7 % generation on Llama 2; a MUL_MAT_ID abort fixed) and the reasons for the remaining gap (launch serialization, fusion, memory bandwidth). |
| 28 Oct | **GPU usage per client** for the Rust `asahi` driver: a `show_fdinfo` hook missing from the Rust DRM abstraction. In test. |
| 27-28 Oct | **A public macOS reference dataset of this machine:** 45 runs under macOS 13, 14 and 15 (device trees, IORegistry, Neural Engine, SMC, Metal and MoltenVK benchmarks, input reports), so Linux work needs no macOS boot. |
| 14-29 Oct | **33 disks of 18 TB moved from HFS+ to XFS in place**, every copy verified before its source was formatted, then pooled, with four parity disks set up for SnapRAID. |
| 18 Oct | **Desktop fixes ready for upstream:** the KDE task switcher dropping windows traced to a rounding in libplasma; a Magic Mouse driver change that stops a resting finger from scrolling. |

## Results

What works on my machine today, with where its code and evidence live. Dates are 2026.

**Thunderbolt/USB4 storage on Apple silicon** (`src-patches/linux/tbt-7.1`, `tbt-pcie`, `kernel/tbt-kernel.sh`)
- PCIe tunnelled over USB4 to ASM2464 enclosures: a port of the Apple-side controller driver (`apciec`) and its
  device-tree nodes, a DART address-offset fix, cable-speed and role fixes in `thunderbolt/apple` and `tipd`.
- Links train at 20 Gb/s per lane, two lanes; four such enclosures with 32 SATA disks came up at boot and survived
  eject, unplug and replug (11-21 Oct).
- The same kernel drives Thunderbolt 3 too, with no change: two 24-bay boxes (Intel JHL7440 bridge, LSI SAS3008 HBA,
  SAS expander) at 40 Gb/s hold all 33 disks since 22 Oct.
- Backported onto Asahi's 7.1.13 kernel (from the 7.2 work-in-progress tree), so one kernel keeps the GPU driver
  and the disks.

**The M2 Ultra Neural Engine under Linux** (`kernel/dt/`, `src-patches/linux-ane/m2-ultra-dart-power`,
`kernel/ane.sh`)
- omarchy-ane's T6022 overlay panicked the boot (SError in `apple_dart_probe`). macOS's power tables on the same
  machine put the ANE DARTs under the `ANE_SYS` island, not an always-on one; with that change the machine boots.
- Firmware boot, channel table validated, smoke test 20/20 bit-exact against the reference, 0.418 ms median
  (29 Oct). Merged into omarchy-ane the same day (pull request 278) with its receipt.

**llama.cpp on the GPU: Vulkan (Honeykrisp) against Metal** (`src-patches/llama.cpp/honeykrisp`, `src-patches/mesa`,
`gpu/`)
- Matrix tile sizes for this GPU: prompt processing +12-23 %; Qwen3-Coder-Next Q8 at 2048 tokens 672 -> 780 t/s.
- Batches of 9-64 tokens: the matrix-vector path is used beyond its fixed 8-column limit (settable, then 16
  columns); a 9-token Qwen batch 37 -> 107 t/s, which makes speculative decoding pay: a code edit with n-gram drafts
  30 -> 55-59 t/s.
- A MUL_MAT_ID abort with offset tensors found and fixed (955/955 tests pass).
- Mesa compiler series (load-only bit 47 on `lload`, an ILP scheduler from another contributor) built and measured.
- A q4_0/q8_0 matrix-vector shader laid out like Metal's kernels (opt-in, `GGML_VK_MMV_SIMD=1`): one 4096x14336
  step 81 -> 68 us (q4_0) and 160 -> 128 us (q8_0); generation +7 % on Llama 2, +4 % on Qwen.
- Measured against Metal on the same machine (27-29 Oct): llama.cpp's Vulkan backend through MoltenVK on macOS is
  no faster than Honeykrisp on Linux, so most of the 2-3x gap is in the Vulkan shaders and graph; Metal's graph
  fusion is worth 22-25 % of generation on Qwen and Gemma. Plain f16 streams at 475 GB/s on Linux against 820 on
  Metal, a part of the gap below llama.cpp still open.

**GPU usage per client** (`src-patches/linux/asahi-fdinfo`)
- `drm-engine-*` and `drm-memory-*` fdinfo lines for the Rust `asahi` driver, through a `show_fdinfo` hook in the
  Rust DRM abstraction, the GEM file operations included. In test.

**macOS reference data** (`macos/`, `results/`)
- One macOS boot of my machine collects what Linux work needs without booting macOS again: device tree and
  IORegistry, Neural Engine nodes and firmware hashes, Thunderbolt/PCIe trees, SMC keys idle and under load, Metal
  launch cost, llama.cpp with Metal and with Vulkan on MoltenVK, Metal's fusion ablation, per-op timings, Core ML on
  the Neural Engine, input-device reports with the touches and events macOS derives from them. Serial numbers, UUIDs
  and network addresses are replaced. The runs of 27-28 Oct under macOS 13, 14 and 15 are in `results/macos/`.

**Storage server** (`storage/`, `migrate-row.sh`)
- 33 disks of 18 TB in two 24-bay Thunderbolt 3 boxes: 594 TB (540 TiB) raw. 28 data disks make one mergerfs pool of
  504 TB (459 TiB), 378 TB (344 TiB) in use; four parity disks for SnapRAID. The goal is 48 disks, both boxes full:
  864 TB (786 TiB) raw, 756 TB (688 TiB) of data with six parity disks.
- Moved from HFS+ to XFS in place, disk by disk, each copy verified by size and time and by reading samples back;
  files macOS keeps compressed (which Linux reads as empty) detected and held. The last disk is still copying.
- Mounts by label that tolerate an absent disk; SnapRAID nightly sync and weekly scrub timers ready for after the
  first sync.

**Desktop** (`desktop/`, `src-patches/linux/hid-*`)
- Magic Mouse: no scroll from a resting finger while the mouse moves (in the driver); Magic Keyboard: optional Fn
  shortcuts in `hid-apple`; KWin, Konsole and Plasma fixes, a Qt style that keeps the wheel off unfocused controls,
  the WhiteSur look, SF fonts, the TV's colour profile, Bluetooth pairings taken over from macOS.

## Layout

| Path | What |
|---|---|
| `setup.sh` | a fresh Fedora Asahi install to my machine's state; snapshots and restore |
| `kernel/` | build, install and switch the trial kernel (`tbt-kernel.sh`), the HID drivers, the Neural Engine (`ane.sh`), device-tree overlays (`dt/`) |
| `src-patches/PROJECT/SERIES/` | each fork's changes as a patch series on a pinned commit (`BASE`); `publish.sh` turns one into its fork's branch |
| `gpu/` | llama.cpp runs and benchmarks, Mesa builds beside the system one, `vk-chain` launch microbenchmarks (Vulkan and Metal) |
| `storage/` | SnapRAID and the pool, backups, the Thunderbolt disks' udev rules, disk tools |
| `desktop/` | input, look, fonts, colour, Bluetooth |
| `system/` | machine settings, programs, audit, power and network logging |
| `macos/` | the macOS collection kit |
| `hardware/` | the same machine as Linux describes it |
| `results/` | measurements and macOS reference data |
| `tests/` | loop-device tests of the storage tools |
| `KNOWLEDGE.md` | findings with their evidence; `_gtd/` the task board |

`src/` (fork clones), `build/` and `var/` (local runs) are not tracked.

## Start

    curl -fsSLO https://raw.githubusercontent.com/Ophuscado/linux-lab/master/setup.sh
    bash setup.sh all

The kernel: `kernel/tbt-kernel.sh` (`deps`, `build`, `install`, then reboot). Kernel and device trees are switched
together; `previous` and `boot.bin.previous` undo an install. The header of the script lists every stage and what it
touches.

## License

GPL-2.0-or-later (`LICENSE`). Patch series keep the licence of the project they apply to.
