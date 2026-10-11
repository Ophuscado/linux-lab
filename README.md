# asahi-usb4-lab

Getting USB4/Thunderbolt storage enclosures to work under Fedora Asahi Remix on an
Apple Mac Studio (M2 Ultra, 2023). Personal lab work, not an Asahi Linux project.

The diagnosis, scripts and kernel patches here were produced with an LLM assistant
(Claude) and tested on one machine. Asahi Linux does not accept LLM-assisted
contributions (https://asahilinux.org/llm-policy/), so none of this is submitted there.

## What works

- USB4 link to an ASM2464 enclosure trains at 20 Gb/s per lane, dual lane.
- PCIe over Thunderbolt, a port of Sven Peter's 2023 driver for the Mac-side controller
  behind each port (`apciec`): the enclosure's AHCI controller and its eight disks come
  up, and come back after an eject, unplug and replug. Seen on the 7.2-based trial kernel.

## What is written but not yet run

- Branch `tbt/7.1`: the same on the stock kernel's 7.1 source, which keeps the GPU driver.
  This is what `tbt-kernel.sh` builds now.

## What does not yet

- Pulling an enclosure whose disks are busy is untested; it froze the machine once in an
  earlier, broken state. Use `./tbt-kernel.sh umount` and `eject` first.

## Contents

- `tbt-kernel.sh`: build, install, switch between trial and stock kernel, roll back.
- `tbt-capture.sh`: record a plug-in on the trial kernel with driver debug output.
- `boot-dump.sh`: record what the running kernel brought up, for comparing kernels.
- `apciec-dump.sh`: collect, in macOS, how the Thunderbolt PCIe controller is described.
- `patches/`: the lab's own kernel changes as a series against `asahi-wip-7.2` at
  `236788cd2602` (branch `tbt/pcie` of https://github.com/Ophuscado/linux). The kernel the
  script builds is branch `tbt/7.1` of the same fork: these changes plus the backported
  USB4 stack on the stock 7.1 source.
- `llama-bench.sh`: llama.cpp speed on the CPU and through Vulkan, on the running kernel.
- `bt-sync.sh`: give Linux the Bluetooth pairings macOS made, replacing stale Linux ones.
- `KNOWLEDGE.md`: findings that were expensive to obtain, with their evidence.
- `_gtd/`: the task board.

## Start here

1. Read the header of `tbt-kernel.sh`; it lists the stages and what each one touches.
2. `./tbt-kernel.sh deps`, `build`, `install`, `try`, reboot.
   `try` and `stock` switch kernel and device trees together; do not pick the other
   kernel in the GRUB menu, the stock kernel hangs on the trial device trees.
3. `./tbt-kernel.sh status`, then `./tbt-capture.sh` for a detailed record.
   Disks behind PCIe over Thunderbolt appear read-only until `./tbt-kernel.sh readonly off`.
   `./tbt-kernel.sh mount` mounts their HFS+ volumes under `/mnt/tbt`, `bench` measures
   read speed, `umount` and `eject` come before unplugging.
4. `./tbt-kernel.sh rollback` restores the stock kernel, device trees and boot image.
