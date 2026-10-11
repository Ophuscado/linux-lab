# asahi-usb4-lab

Getting USB4/Thunderbolt storage enclosures to work under Fedora Asahi Remix on an
Apple Mac Studio (M2 Ultra, 2023). Personal lab work, not an Asahi Linux project.

The diagnosis, scripts and kernel patches here were produced with an LLM assistant
(Claude) and tested on one machine. Asahi Linux does not accept LLM-assisted
contributions (https://asahilinux.org/llm-policy/), so none of this is submitted there.

## What works

- Trial kernel (Asahi `asahi-wip-7.2` plus this lab's branch) built and booted next to the stock one.
- USB4 link to an ASM2464 enclosure trains at 20 Gb/s per lane, dual lane.
- Enclosure falls back to USB 3 at 10 Gb/s when its PCIe tunnel gets no answer.

## What is written but not yet run

- PCIe over Thunderbolt: a port of Sven Peter's 2023 driver for the Mac-side PCIe
  controller behind each port (`apciec`), with device-tree nodes for the Mac Studio.
  Until it has run, the disks of an enclosure that only tunnels PCIe do not appear.

## What does not

- No GPU acceleration on the trial kernel: the branch marks the GPU driver broken.

## Contents

- `tbt-kernel.sh`: build, install, switch between trial and stock kernel, roll back.
- `tbt-capture.sh`: record a plug-in on the trial kernel with driver debug output.
- `boot-dump.sh`: record what the running kernel brought up, for comparing kernels.
- `apciec-dump.sh`: collect, in macOS, how the Thunderbolt PCIe controller is described.
- `patches/`: the kernel changes, against `asahi-wip-7.2` at `236788cd2602`; the same
  commits are branch `tbt/pcie` of https://github.com/Ophuscado/linux, which the script builds.
- `KNOWLEDGE.md`: findings that were expensive to obtain, with their evidence.
- `_gtd/`: the task board.

## Start here

1. Read the header of `tbt-kernel.sh`; it lists the stages and what each one touches.
2. `./tbt-kernel.sh deps`, `TBT_NO_GPU=1 ./tbt-kernel.sh build`, `install`, `try`, reboot.
   `try` and `stock` switch kernel and device trees together; do not pick the other
   kernel in the GRUB menu, the stock kernel hangs on the trial device trees.
3. `./tbt-kernel.sh status`, then `./tbt-capture.sh` for a detailed record.
   Disks behind PCIe over Thunderbolt appear read-only until `./tbt-kernel.sh readonly off`.
4. `./tbt-kernel.sh rollback` restores the stock kernel, device trees and boot image.
