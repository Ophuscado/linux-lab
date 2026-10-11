# asahi-usb4-lab

Getting USB4/Thunderbolt storage enclosures to work under Fedora Asahi Remix on an
Apple Mac Studio (M2 Ultra, 2023). Personal lab work, not an Asahi Linux project.

The diagnosis, scripts and kernel patches here were produced with an LLM assistant
(Claude) and tested on one machine. Asahi Linux does not accept LLM-assisted
contributions (https://asahilinux.org/llm-policy/), so none of this is submitted there.

## What works

- Trial kernel (Asahi `asahi-wip-7.2`, pinned commit) built and booted next to the stock one.
- USB4 link to an ASM2464 enclosure trains at 20 Gb/s per lane, dual lane.
- Enclosure falls back to USB 3 at 10 Gb/s when its PCIe tunnel gets no answer.

## What does not

- No disks: the enclosure only tunnels PCIe, and the Mac-side PCIe controller behind the
  tunnel (`apciec`) has no Linux driver.
- No GPU acceleration on the trial kernel: the branch marks the GPU driver broken.

## Contents

- `tbt-kernel.sh`: build, install, one-shot boot, patch and roll back the trial kernel.
- `tbt-capture.sh`: record a plug-in on the trial kernel with driver debug output.
- `apciec-dump.sh`: collect, in macOS, how the Thunderbolt PCIe controller is described.
- `patches/`: the kernel changes, against `asahi-wip-7.2` at `236788cd2602`.
- `KNOWLEDGE.md`: findings that were expensive to obtain, with their evidence.
- `_gtd/`: the task board.

## Start here

1. Read the header of `tbt-kernel.sh`; it lists the stages and what each one touches.
2. `./tbt-kernel.sh deps`, `TBT_NO_GPU=1 ./tbt-kernel.sh build`, `patch`, `install`, `try`, reboot.
3. `./tbt-kernel.sh status`, then `./tbt-capture.sh` for a detailed record.
4. `./tbt-kernel.sh rollback` restores the stock kernel, device trees and boot image.
