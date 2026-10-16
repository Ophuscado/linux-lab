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
  up, and come back after an eject, unplug and replug.
- All of that on the stock kernel's 7.1 source (branch `tbt/7.1`, what `tbt-kernel.sh`
  builds), which keeps the GPU driver: one kernel for the desktop and the enclosure.

## Starting from a fresh install

    curl -fsSLO https://raw.githubusercontent.com/Ophuscado/linux-lab/main/setup.sh
    bash setup.sh all

It clones this repository, takes over the Bluetooth pairings macOS made, snapshots the
clean system, builds and installs the kernel and installs what the measuring scripts need.
`setup.sh restore NAME` puts the system back to a snapshot later.

## What does not yet

- Pulling an enclosure whose disks are busy is untested; it froze the machine once in an
  earlier, broken state. Use `./tbt-kernel.sh umount` and `eject` first.

## Contents

- `reinstall-prep.sh`: in macOS, remove the old Linux partitions and size macOS for the new install.
- `setup.sh`: bring a fresh install to the lab's state; snapshot and restore the system.
- `tbt-kernel.sh`: build, install, switch between trial and stock kernel, roll back.
- `tbt-capture.sh`: record a plug-in on the trial kernel with driver debug output.
- `boot-dump.sh`: record what the running kernel brought up, for comparing kernels.
- `apciec-dump.sh`: collect, in macOS, how the Thunderbolt PCIe controller is described.
- `patches/`: the lab's own kernel changes as a series against `asahi-wip-7.2` at
  `236788cd2602` (branch `tbt/pcie` of https://github.com/Ophuscado/linux). The kernel the
  script builds is branch `tbt/7.1` of the same fork: these changes plus the backported
  USB4 stack on the stock 7.1 source.
- `llama-bench.sh`: llama.cpp speed on the CPU and the GPU (Vulkan in Linux, Metal in macOS), with
  per-operation Vulkan timings.
- `llama-sweep.sh`: try llama.cpp's mat-vec settings on this GPU, check the fastest against the CPU.
- `mesa-side.sh`: build another Mesa Vulkan driver beside the system one and run programs with it.
- `bt-sync.sh`: give Linux the Bluetooth pairings macOS made, replacing stale Linux ones.
- `ux-fix.sh`: Magic Mouse without false middle clicks or drift scrolls; no middle-click paste.
- `disk-blink.sh`: make one disk blink to find it in the box.
- `disk-inventory.sh`: map every enclosure disk to row, slot, serial and volume fill.
- `migrate-row.sh`: move the four rows of disks from HFS+ into one XFS pool, disk by disk, verified, leaving the parity disks empty; a pool disk that stops answering is dropped and the copy goes on.
- `snapraid-setup.sh`: the final layout after the migration: mounts by label, the mergerfs pool, SnapRAID with four parity disks.
- `power-dump.sh`: record power sensors, link power states and disk settings before tuning.
- `netlog.sh`: send kernel messages to a second computer, so a freeze leaves a log.
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
