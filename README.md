# linux-lab

A personal lab for improving Linux support on an Apple Mac Studio with M2 Ultra (`j475d`). My machine runs Fedora
Asahi Remix, and this repository is what it takes to make it a complete Linux machine. Everything here is tested on
that one machine, kept as patch series on pinned upstream commits so each piece can be rebuilt and proposed upstream on
its own. The findings and their evidence are in [`KNOWLEDGE.md`](KNOWLEDGE.md).

## Against stock Asahi

What this lab adds on this machine over Fedora Asahi Remix's own kernel and Mesa, each piece usable on its own. The
numbers are this Mac's, measured the same way on both sides; macOS's, on the same machine, in brackets.

| Area | Stock Asahi on the M2 Ultra | This lab | Where |
|---|---|---|---|
| Memory and fabric power management (PMP) | not started on this chip: memory and fabric stay in one fixed state | started (by hand, after each boot): idle 21.3 -> 16.1 W (16.2-16.7), GPU read 668 -> 775 GB/s (755-763), llama.cpp generation +14-20 % | [`kernel/pmp.sh`](kernel/pmp.sh), `kernel/pmp/`, `kernel/dt/t6022-pmp.dts` |
| Thunderbolt and USB4 storage | no PCIe over USB4 on this chip | PCIe tunnelled over USB4; Thunderbolt 3 boxes at 40 Gb/s | `src-patches/linux/tbt-7.1`, `tbt-pcie` |
| Neural Engine | not in Fedora Asahi Remix; omarchy-ane's overlay panicked the boot on this chip | runs, bit-exact; the fix is merged in omarchy-ane | `kernel/dt/`, `kernel/ane.sh` |
| llama.cpp on the GPU (Vulkan) | upstream llama.cpp on Honeykrisp | 16 patches: prompts +12-23 % and more, generation over long contexts up to 4.6x, speculative decoding pays | `src-patches/llama.cpp/honeykrisp`, `gpu/` |
| GPU timings and per-program usage | per-op timestamps booked one op early; no fdinfo in the Rust driver | timestamps fixed; GPU memory per program in fdinfo | `src-patches/mesa/agxperf`, `src-patches/linux/asahi-fdinfo` |
| Magic Mouse, Trackpad, Keyboard | default speeds, no Fn shortcuts | macOS's pointer speed and scrolling, Fn shortcuts | `src-patches/linux/hid-*`, `desktop/` |

## What it does

**Memory and fabric power management** ([`kernel/pmp.sh`](kernel/pmp.sh), `kernel/pmp/`, `kernel/dt/t6022-pmp.dts`)
- The M2 Ultra's power management processor (PMP) runs under Linux: it moves memory and fabric between their
  performance states by what the devices ask for, as macOS does. Without it Linux leaves them in one fixed state:
  too high at idle, too low under GPU load. Asahi does not start it on this chip.
- Measured the same way off and on, one run each (`results/linux/pmp-20261104`), macOS in brackets: idle
  21.32 -> 16.08 W (16.2-16.7 W); GPU read at 1 GB 668 -> 775 GB/s (755-763), in cache (16 MB) 998 -> 1818 GB/s (1909);
  llama.cpp generation +14-20 %, prompts +1-5 %.
- What it took, found by tracing macOS starting the PMP under m1n1's hypervisor ([`macos/hv-pmp.sh`](macos/hv-pmp.sh))
  and diffing the trace against Asahi's driver: start with the device-request word macOS has (the CPU clusters and
  the GPU, which Linux's tree never requests), and answer the firmware's property lookups numbered as macOS does.
  The lab's own first tool wrote that request register through a posted mapping, which hung the machine on every
  try until it was mapped non-posted. KNOWLEDGE.md, Power management, has each step, the evidence and what is open.
- Today it is started by hand after each boot (`TBT_OVERLAYS="t6022-ane t6022-pmp" kernel/tbt-kernel.sh dtb` once,
  then `kernel/pmp.sh build`, `votes`, `start --now`); starting it at boot from the kernel series is next.

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
  ([pull request 278](https://github.com/joshuaswarren/omarchy-ane/pull/278)), its first M2 Ultra report, and the
  passing row that turned the chip on by default there.

**llama.cpp on the GPU** ([`gpu/`](gpu/), [`src-patches/llama.cpp/honeykrisp`](src-patches/llama.cpp/honeykrisp))
- Vulkan (Honeykrisp) measured against Metal on the same machine, and moved forward by sixteen patches and their
  settings: prompts +12-23 % from the tile shape, Llama 2 +18 % more from 16x16x16 matrices (the driver offers 8x8x8
  first), short MoE prompts up to +22 % from the expert tile, 9-token batches 3x faster (so speculative decoding pays:
  a code edit 30 to 55-59 t/s), a Metal-style matrix-vector shader, an abort fixed, and generation over long contexts
  up to 4.6x faster (Llama 2 at 16k tokens 6.6 to 30.5 t/s: the driver reports no core count, so attention was split
  for 16 cores), and MoE prompts +4-15 % from a serial loop before every expert matmul.
- Per-op timings under Honeykrisp were booked one op early (a driver timestamp bug, fixed in
  [`src-patches/mesa/agxperf`](src-patches/mesa/agxperf)); measured right, the experts' matmuls are 49-80 % of a MoE
  prompt.
- Where the remaining gap is: for prompts, the matmul's global loads (weights and activations), which do not overlap its matrix work
  (the matrix loop alone runs near the hardware's rate for its grid, 15.4 of 26.5 TFLOPS, see `gpu/vk-chain` mma);
  for generation, partly the memory and fabric state (the PMP gives +14-20 %, above), the rest the cost of each
  dependent GPU launch, not fusion.

| Tokens/s, pp512 / tg128 | Metal | Vulkan via MoltenVK | Honeykrisp, 31 Oct | Honeykrisp, 1 Nov | 4 Nov, PMP off | 4 Nov, PMP on | Share of Metal |
|---|---|---|---|---|---|---|---|
| Llama 2 7B Q4_0 | 1517 / 120.4 | 788 / 59.9 | 874 / 68.1 | 873 / 67.8 | 876 / 71.2 | 896 / 81.4 | 0.59 / 0.68 |
| GPT-OSS 20B UD-Q8_K_XL | 1944 / 124.5 | 992 / 82.7 | 1005 / 70.6 | 1049 / 71.3 | 1053 / 74.0 | 1109 / 84.5 | 0.57 / 0.68 |
| GPT-OSS 120B UD-Q4_K_XL | 1001 / 94.2 | - | 526 / 49.5 | 542 / 49.3 | - | - | 0.54 / 0.52 |
| Gemma 4 26B-A4B UD-Q4_K_XL | 2100 / 95.2 | - | 836 / 38.6 | 902 / 37.7 | - | - | 0.43 / 0.40 |
| Qwen3-Coder-Next 80B-A3B UD-Q8_K_XL | 1535 / 67.8 | 422 / 24.8 | 583 / 34.5 | 686 / 34.6 | 741 / 36.9 | 779 / 44.4 | 0.51 / 0.65 |

A fresh clone reaches this with `gpu/llama-build.sh` (clones llama.cpp at `src-patches/llama.cpp/honeykrisp`'s pinned commit, applies the series with `git am`, builds `src/llama.cpp-simd/build/bin`, checked here against a real Vulkan run); `llama-run.sh` and `llama-compare.sh` read it from there. Both Honeykrisp columns run Mesa's `agxperf` side driver (`gpu/mesa-side.sh`: the coopmat series plus three unmerged Asahi compiler changes), not upstream Mesa's own Honeykrisp; `results/*/driver.txt` names it per run. Metal and MoltenVK: macOS 15.8.1, 28 Oct ([`results/macos`](results/macos)). Honeykrisp, 1 Nov: the 15 patches on llama.cpp's master of that day, at `llama-compare.sh STEPS=bench`'s own settings (-ub 2048, f16 KV cache — not the server's -ub 8192 / q8_0 KV from `llama-run.sh`; see the BACKLOG line on whether to rebench at those) ([`results/linux/compare-20261101-043729`](results/linux/compare-20261101-043729), `llama-compare.sh STEPS=bench`); 31 Oct: the first 14 on the master of 25 Oct ([`results/linux/compare-20261031-063537`](results/linux/compare-20261031-063537)). 4 Nov: the same build both times (the 16 patches on `a91eab67d`, the same `STEPS=bench` settings), with the power management processor off (01:12, the lab's usual tree) and on (07:20, the `t6022-pmp` tree), through `kernel/pmp.sh measure` ([`results/linux/pmp-20261104`](results/linux/pmp-20261104)); not run for the 120B and Gemma. Share of Metal: the newest column over Metal's (4 Nov PMP on where it ran, else 1 Nov). Models: the exact files, their Hugging Face sources and sha256 in [`macos/models.md`](macos/models.md) (`UD-` is Unsloth Dynamic, a per-tensor mix on a Q8_0 or Q4_K_M base).

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
- Magic Mouse and Trackpad as smooth as on my macOS settings, or better: the pointer speed measured from macOS (0.875,
  no acceleration), key repeat and scrolling matched (natural scrolling off, as this Mac has it; `NATURAL_SCROLL=true
  desktop/ux-fix.sh input on` picks macOS's own factory default instead), and no scrolling from a finger resting on
  the mouse. Magic Keyboard Fn shortcuts (Fn+F maximize, Fn+C centre, Fn+P keep above, Fn+D on all desktops) need the
  lab's hid-apple patch active — `kernel/applekbd.sh try` turns it on against the running kernel without a reboot —
  then the four keys it frees are bound in System Settings > Keyboard > Shortcuts > KWin. Still to come: a screen
  zoom from a tap (two fingers on the mouse, three on the trackpad).
- Keyboard layout as on macOS (`desktop/ux-fix.sh keyboard on`): UK ISO by default (`gb`/`mac`/`applealu_iso`); a US
  ANSI keyboard is `XKB_LAYOUT=us XKB_VARIANT=mac XKB_MODEL=applealu_ansi ux-fix.sh keyboard on`. Cmd becomes Linux's
  own modifier key (Super): it opens launchers and the Cmd+Tab switcher, and keeps a couple of KWin's own shortcuts
  (Cmd+Up/Down tiles a window); Ctrl still does the ordinary in-app shortcuts (copy, paste, save) that macOS gives to
  Cmd. Right Cmd composes accents instead (right Cmd, `~`, `n` → `ñ`).
- The KDE task switcher bug traced to libplasma, the WhiteSur look, macOS's colour profile for the TV, Bluetooth
  pairings from macOS.

**Not yet** (searchable in [`_gtd/BACKLOG.md`](_gtd/BACKLOG.md) or [`_gtd/TODO.md`](_gtd/TODO.md) by the quoted phrase)
- The power management processor at boot: today it is started by hand after each boot ("PMP on at every boot").
- HDR on the HDMI output: KScreen reports it as HDR-incapable on Linux, while macOS drives the same display in HDR ("HDR on the HDMI output").
- Hardware video decode: no VA-API driver exists for the Apple GPU's media engine (checked here: no Apple/Asahi `*_drv_video.so`, only AMD/NVIDIA/d3d12/virtio ones ship); software decode only ("video decode").
- Bluetooth after suspend: the keyboard's `hci0` can time out on resume; a mitigation isn't picked yet ("Bluetooth-after-suspend fault").

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

About 45 minutes, almost all of it the kernel build; it ends asking to reboot. The `kernel` stage makes
two changes that ask first, or run with `LAB_YES=1` for no question: Thunderbolt/USB4 devices get
authorized as they appear instead of per-device, and the lab's own kernel becomes the one the next boot
starts (the stock kernel stays in the boot menu; `setup.sh restore NAME` undoes it). Needs sudo, a
terminal, a btrfs root split into `root` and `home` subvolumes; built against the kernel in
`setup.sh`'s `EXPECT_KERNEL` and warns, not blocks, on another. `setup.sh plan` prints this without
doing anything, if you'd rather see it first.

    curl -fsSLO https://raw.githubusercontent.com/Ophuscado/linux-lab/master/setup.sh
    bash setup.sh all

The kernel: `kernel/tbt-kernel.sh deps`, `build`, `install`, then reboot; `previous` undoes an install.

## License

GPL-2.0-or-later (`LICENSE`); the kernel patches GPL-2.0-only, as the kernel; each patch series keeps its project's.
