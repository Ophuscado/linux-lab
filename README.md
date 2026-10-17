# asahi-usb4-lab

An Apple Mac Studio (M2 Ultra, 2023) under Fedora Asahi Remix as storage server and
workstation: four home-made 8-bay USB4 disk boxes, their 32 disks in one pool with
SnapRAID, the GPU for llama.cpp. Personal lab work, not an Asahi Linux project.

## Goals

1. USB4/Thunderbolt disk boxes on Linux (ASM2464, PCIe over Thunderbolt): `tbt-kernel.sh`.
2. The 32 disks from HFS+ into one XFS mergerfs pool, every copy verified before its source
   is formatted: `migrate-row.sh`.
3. SnapRAID over the pool, four parity disks, nightly sync and weekly scrub: `snapraid-setup.sh`.
4. A quiet, efficient machine: idle disks and controllers powered down, suspend and replug
   without a freeze: `settings.sh`, `power-dump.sh`, `netlog.sh`.
5. llama.cpp on the GPU (Vulkan) close to what Metal does in macOS: `llama-bench.sh`,
   `llama-sweep.sh`, `mesa-side.sh`.
6. The desktop as comfortable as macOS: Magic Mouse, no middle-click paste, Bluetooth pairings
   shared with macOS: `ux-fix.sh`, `bt-sync.sh`.

Where each stands: `_gtd/` (DOING is what runs or waits now, TODO the current sprint, the
migration); standing decisions and findings: `KNOWLEDGE.md`.

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
- `backup-home.sh`: back up your home to the backup disk with restic, kept like Time Machine (hourly for a day, daily for a month, weekly before that, the oldest dropped above 80 % full), one run at a time, lowest priority, without caches, trash and the migration's logs; password in `~/.config/restic/password`.
- `disk-check.sh`: read-only health check of one disk, for a USB disk that hangs: link, SMART, kernel lines, three timed reads, a short self-test.
- `disk-inventory.sh`: map every enclosure disk to row, slot, serial and volume fill.
- `migrate-row.sh`: move the four rows of disks from HFS+ into one XFS pool, disk by disk, verified, leaving the parity disks empty; a pool disk that stops answering is dropped and the copy goes on; `extra` copies the external USB disk 33 the same way; `readtest` checks one box's links by reading all its disks at once; `policy` switches where new files go (pfrd spreads them, mfs fills the emptiest disk first); `pause`, `resume` and `rest 15` stop rows, or let them take turns to rest, so the boxes cool; `eager on` adds each verified disk to the pool 30 minutes after its verify instead of when the pool needs room; a disk holding files macOS keeps compressed (Linux reads them as empty) is held, never formatted, until `rescued`; before any format a sample of the disk's copies is read back from the disks and compared (`sample`); `restart` puts running rows on a new version of the script.
- `settings.sh`: install or remove the lab's machine settings in one go (Thunderbolt authorize, disk spin-down, the desktop fixes, a cap on unwritten data per USB disk, SnapRAID timers once set up); `sleep-hook` ejects the boxes around suspend (off by default, untested).
- `snapraid-setup.sh`: the final layout after the migration: mounts by label, the mergerfs pool, SnapRAID with four parity disks.
- `power-dump.sh`: record power sensors, link power states and disk settings before tuning.
- `netlog.sh`: send kernel messages to a second computer, so a freeze leaves a log.
- `KNOWLEDGE.md`: findings that were expensive to obtain, with their evidence.
- `tests/`: loop-device tests of `migrate-row.sh` and `snapraid-setup.sh`, run as root in a scratch Linux box; each states what it expects.
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
