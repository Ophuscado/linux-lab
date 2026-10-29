# linux-lab

A personal lab for improving Linux support on an Apple Mac Studio with M2 Ultra (2023, `j475d`). My machine runs
Fedora Asahi Remix, and this repository is what it takes to make it a complete Linux machine: kernel work for Thunderbolt/USB4 storage and the Neural Engine, GPU compute for local language models
measured against macOS on the same hardware, a 33-disk storage server, and a desktop close to macOS.

Everything here is tested on that one machine. It is a layer on top of upstream projects (Asahi Linux, Mesa,
llama.cpp, omarchy-ane): changes are kept as patch series against pinned upstream commits, so each can be rebuilt,
published and proposed upstream on its own. The findings, with their evidence and dates, are in `KNOWLEDGE.md`.

## Results

What works on my machine today, with where its code and evidence live. Dates are 2026.

**Thunderbolt/USB4 storage on Apple silicon** (`src-patches/linux/tbt-7.1`, `tbt-pcie`, `kernel/tbt-kernel.sh`)
- PCIe tunnelled over USB4 to ASM2464 enclosures: a port of the Apple-side controller driver (`apciec`) and its
  device-tree nodes, a DART address-offset fix, cable-speed and role fixes in `thunderbolt/apple` and `tipd`.
- Links train at 20 Gb/s per lane, two lanes; four enclosures with 32 SATA disks come up at boot and survive
  eject, unplug and replug.
- Backported onto Asahi's 7.1.13 kernel (from the 7.2 work-in-progress tree), so one kernel keeps the GPU driver
  and the enclosures.

**The M2 Ultra Neural Engine under Linux** (`kernel/dt/`, `src-patches/linux-ane/m2-ultra-dart-power`, `kernel/ane.sh`)
- omarchy-ane's T6022 overlay panicked the boot (SError in `apple_dart_probe`). macOS's power tables on the same
  machine put the ANE DARTs under the `ANE_SYS` island, not an always-on one; with that change the machine boots.
- Firmware boot, channel table validated, smoke test 20/20 bit-exact against the reference, 0.418 ms median
  (29 Oct). Prepared as a pull request to omarchy-ane with its receipt.

**llama.cpp on the GPU: Vulkan (Honeykrisp) against Metal** (`src-patches/llama.cpp/honeykrisp`, `src-patches/mesa`, `gpu/`)
- Matrix tile sizes for this GPU: prompt processing +12-23 %; Qwen3-Coder-Next Q8 at 2048 tokens 672 -> 780 t/s.
- Batches of 9-64 tokens: the matrix-vector path is used beyond its fixed 8-column limit (settable, then 16
  columns); a 9-token Qwen batch 37 -> 107 t/s, which makes speculative decoding pay: a code edit with n-gram drafts
  30 -> 55-59 t/s.
- A MUL_MAT_ID abort with offset tensors found and fixed (955/955 tests pass).
- Mesa compiler series (load-only bit 47 on `lload`, an ILP scheduler from another contributor) built and measured.
- A q4_0/q8_0 matrix-vector shader laid out like Metal's kernels (opt-in, `GGML_VK_MMV_SIMD=1`): one 4096x14336
  step 81 -> 68 us (q4_0) and 160 -> 128 us (q8_0); generation +5 % on Llama 2, +2 % on Qwen.
- Measured against Metal on the same machine (27-29 Oct): llama.cpp's Vulkan backend through MoltenVK on macOS is
  no faster than Honeykrisp on Linux, so most of the 2-3x gap is in the Vulkan shaders and graph; Metal's graph
  fusion is worth 22-25 % of generation on Qwen and Gemma. Plain f16 streams at 475 GB/s on Linux against 820 on
  Metal, a part of the gap below llama.cpp still open.

**GPU usage per client** (`src-patches/linux/asahi-fdinfo`)
- `drm-engine-*` and `drm-memory-*` fdinfo lines for the Rust `asahi` driver, through a `show_fdinfo` hook in the
  Rust DRM abstraction, the GEM file operations included. In test.

**macOS reference data** (`macos/`, `results/`)
- One macOS boot of my machine collects what Linux work needs without booting macOS again: device tree and IORegistry, Neural
  Engine nodes and firmware hashes, Thunderbolt/PCIe trees, SMC keys idle and under load, Metal launch cost,
  llama.cpp with Metal and with Vulkan on MoltenVK, Metal's fusion ablation, per-op timings, Core ML on the Neural
  Engine, input-device reports with the touches and events macOS derives from them. Serial numbers, UUIDs and
  network addresses are replaced. The runs of 27-28 Oct under macOS 13, 14 and 15 are in `results/macos/`.

**Storage server** (`storage/`, `migrate-row.sh`)
- My 33 disks of 18 TB (about 360 TB of data; 32 in four enclosures, one on USB) moved from HFS+ to XFS in place,
  disk by disk, each copy verified by size and time and by reading samples back; files macOS keeps compressed
  (which Linux reads as empty) detected and held. The last disk is still copying.
- One mergerfs pool over the data disks, SnapRAID with four parity disks, mounts by label that tolerate an absent
  disk, nightly sync and weekly scrub timers.

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
| `storage/` | SnapRAID and the pool, backups, the enclosures' udev rules, disk tools |
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
