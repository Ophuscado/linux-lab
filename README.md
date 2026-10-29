# Ophuscado's Lab for Linux on Apple Mac Studio with M2 Ultra

A personal lab for improving Linux support on an Apple Mac Studio with M2 Ultra (`j475d`). My machine runs Fedora
Asahi Remix, and this repository is what it takes to make it a complete Linux machine. Everything here is tested on
that one machine, kept as patch series on pinned upstream commits so each piece can be rebuilt and proposed upstream on
its own. The findings and their evidence are in [`KNOWLEDGE.md`](KNOWLEDGE.md).

## What it does

**Thunderbolt and USB4 storage** ([`kernel/`](kernel/), `src-patches/linux/tbt-7.1`, `tbt-pcie`)
- PCIe tunnelled over USB4 on the M2 Ultra, which Asahi's public USB4 work does not do yet: the Apple-side tunnel
  controller driver ported from a 2023 branch, its DMA address offset found from macOS's tables, cable-speed and role
  fixes. The first public report for this chip that I found.
- The same kernel drives Thunderbolt 3 boxes unchanged: two 24-bay boxes (Intel Titan Ridge bridge, LSI SAS3008, SAS
  expander) at 40 Gb/s.
- Backported onto Asahi's 7.1 kernel, so one kernel has both the GPU driver and the disks.

**The Neural Engine** (`kernel/dt/`, `kernel/ane.sh`)
- The M2 Ultra's Neural Engine runs under Linux: omarchy-ane's overlay panicked the boot until its DARTs were moved
  into the `ANE_SYS` power island that macOS's tables name. The smoke test is bit-exact. Merged into omarchy-ane
  ([pull request 278](https://github.com/joshuaswarren/omarchy-ane/pull/278)), its first M2 Ultra report.

**llama.cpp on the GPU** ([`gpu/`](gpu/), [`src-patches/llama.cpp/honeykrisp`](src-patches/llama.cpp/honeykrisp))
- Vulkan (Honeykrisp) measured against Metal on the same machine, and moved forward by six patches: prompts +12-23 %,
  9-token batches 3x faster (so speculative decoding pays: a code edit 30 to 55-59 t/s), a Metal-style matrix-vector
  shader, an abort fixed.
- Where the remaining gap is: the cost of each dependent GPU launch, not fusion and not memory.

| Tokens/s, pp512 / tg128 | Metal | Vulkan via MoltenVK | Vulkan via Honeykrisp |
|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 120.4 | 788 / 59.9 | 763 / 69.4 |
| GPT-OSS 20B Q8_0 | 1944 / 124.5 | 992 / 82.7 | 820 / 70.4 |
| Qwen3-Coder-Next 80B-A3B Q8_0 | 1535 / 67.8 | 422 / 24.8 | 448 / 34.2 |

**GPU usage per program** (`src-patches/linux/asahi-fdinfo`)
- fdinfo lines for the Rust `asahi` driver, through a `show_fdinfo` hook the Rust DRM layer lacked; memory works, busy
  time needs firmware stamps (a driver option).

**macOS reference data** ([`macos/`](macos/), [`results/macos`](results/macos))
- One macOS boot collects what Linux work needs: device trees, IORegistry, Neural Engine, SMC, Metal and MoltenVK
  benchmarks, input reports. 45 runs under macOS 13, 14 and 15, public.

**Storage server** ([`storage/`](storage/))
- 33 disks of 18 TB, 594 TB (540 TiB) raw, moved from HFS+ to XFS in place, every copy verified before its source was
  formatted. One mergerfs pool of 504 TB (459 TiB), 378 TB (344 TiB) used, and four SnapRAID parity disks. The goal is
  48 disks, both boxes full: 864 TB (786 TiB).

**Desktop** ([`desktop/`](desktop/), `src-patches/linux/hid-*`)
- Magic Mouse without scrolling from a resting finger, Magic Keyboard Fn shortcuts, the KDE task switcher bug traced to
  libplasma, a Qt style that keeps the wheel off unfocused controls, the WhiteSur look, macOS's colour profile for the
  TV, Bluetooth pairings from macOS.

## Layout

| Path | What |
|---|---|
| `setup.sh` | a fresh Fedora Asahi install to this machine's state |
| `kernel/` | build, install and switch the kernel; the Neural Engine; device-tree overlays |
| `src-patches/PROJECT/SERIES/` | each change as a patch series on a pinned commit; `publish.sh` makes it a fork branch |
| `gpu/` | llama.cpp runs, Mesa builds beside the system one, launch and bandwidth microbenchmarks |
| `storage/` | the pool, SnapRAID, backups, disk tools |
| `desktop/`, `system/` | input, look, colour; settings, programs, audit, hardware probe |
| `macos/`, `results/` | the macOS collection kit; measurements |
| `KNOWLEDGE.md`, `_gtd/` | findings; the task board |

## Start

    curl -fsSLO https://raw.githubusercontent.com/Ophuscado/linux-lab/master/setup.sh
    bash setup.sh all

The kernel: `kernel/tbt-kernel.sh deps`, `build`, `install`, then reboot; `previous` undoes an install.

## License

GPL-2.0-or-later (`LICENSE`); the kernel patches GPL-2.0-only, as the kernel; each patch series keeps its project's.
