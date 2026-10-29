# kernel

Kernel patches for Apple silicon Macs running Asahi Linux, and the scripts that build and try
them on Fedora Asahi Remix next to the stock kernel. They come from work on one Mac Studio
(M2 Ultra, 2023, `j475d`) and are tested only there. The series live in `../src-patches/linux/`
(this folder was the linux-patches repository until 27 Oct). None has been submitted upstream yet.

## The patches

**USB4/Thunderbolt disk enclosures** (`src-patches/linux/tbt-pcie`, `tbt-7.1`): ASMedia ASM2464 enclosures with
an AHCI controller and eight SATA disks, on the Mac's USB4 ports.

| Patch | What it does | State |
|---|---|---|
| 0001 thunderbolt: apple | Flag 20 Gb/s per lane for USB4 v2 cables (Enter_USB cable speed 4), so the link trains | Tested: 2 lanes at 20 Gb/s |
| 0002 usb: typec: tipd | Cycle the USB role when a partner leaves USB4 without a disconnect, so its USB 3 fallback is not stuck at USB 2 | Tested: 10000M after the fallback |
| 0003 DEBUG | `cable_info_or` parameter to override the cable information word | Debug only, to be dropped |
| 0004 thunderbolt | Out-of-band protocol adapters: tell a PCIe controller outside the Thunderbolt bus when its tunnel comes and goes | Tested |
| 0005 thunderbolt: apple | Start the tunneled PCIe controller with its tunnel; apply its adapter tunables | Tested |
| 0006 PCI: apple | The PCIe controller behind each USB4 host router ("apciec"), `apple,t8103-usb4-pcie` | Tested |
| 0007 arm64: dts: apple: t602x | Its nodes and IOMMUs for the four host routers of a die; the six ports of the Mac Studio enabled | Tested |
| 0008 iommu: apple-dart | Buses that add an offset to device addresses | Tested |
| 0009 arm64: dts: apple: t602x | The tunneled ports' DARTs: 32-bit addresses with that offset | Tested |

The series was written on Asahi's 7.2 work-in-progress tree, which has the Apple USB4 host
driver (branch `tbt/pcie` of https://github.com/Ophuscado/linux). The kernel the scripts build
is Asahi's `asahi-7.1.13-3` (the stock Fedora kernel's source) with that USB4 stack backported
and the same changes on top, because the 7.2 tree has no GPU driver: branch `tbt/7.1` of the same
fork, pinned in `tbt-kernel.sh`.

Measured with it (2026-10-11): link up 1.1 s after the cable, eight disks about 22 s later;
sequential reads of 267 to 287 MB/s per disk alone and 1.69 GB/s for all eight together,
where the enclosure's own SATA controller (PCIe 8 GT/s x2) is the ceiling; eject, unplug and
replug enumerate again cleanly. The GPU driver works on the same kernel. Details and evidence:
`KNOWLEDGE.md`.

The same kernel also drives Thunderbolt 3 boxes, with no change for them: two 24-bay enclosures,
each an Intel JHL7440 (Titan Ridge) Thunderbolt 3 bridge in front of a Broadcom/LSI SAS3008 HBA
(`mpt3sas`) and a SAS expander. Both train at 40 Gb/s (2 lanes x 20 Gb/s, `boltctl`), and since
22 Oct they have carried a 40-disk copy around the clock (rsync streams of 125 to 131 MB/s per
disk, several at once; not a benchmark) with no Thunderbolt, PCIe or `mpt3sas` error in the kernel
log. So the tunnel is not tied to the ASMedia controller: two controller families, USB4 and
Thunderbolt 3, work through it. Not tried: display tunnels, docks, hot-plug under load.

**Magic Mouse** (`src-patches/linux/hid-magicmouse`): `hid-magicmouse` stops scrolling from a finger that rests
on the surface while the mouse moves (`scroll_hold_ms`, off by default), and gains the macOS
"smart zoom", a two-finger double tap (`smart_zoom`). In use on the Mac Studio since 18 Oct as a
module beside the built-in driver.

**Magic Keyboard** (`src-patches/linux/hid-apple`): `hid-apple` can give Fn+F, Fn+C, Fn+P and Fn+D their own
keys (Prog1 to Prog4, `fn_shortcuts`, off by default) for a desktop to bind, as macOS gives the Fn
(Globe) key shortcuts of its own; here they maximize, centre, keep above and put a window on all
desktops. Built, not yet tried on the Mac.

## Trying them

`tbt-kernel.sh` builds the kernel and installs it as an extra boot entry, leaving the stock one
in place; its header lists every stage. In short:

    ./tbt-kernel.sh deps && ./tbt-kernel.sh build && ./tbt-kernel.sh install
    ./tbt-kernel.sh try        # boot it, with its device trees, until 'stock'
    ./tbt-kernel.sh status     # what the running kernel sees
    ./tbt-kernel.sh stock      # back to the stock kernel and device trees

The device trees are baked into m1n1's boot image for whichever kernel boots, so the kernel and
its device trees are always switched together; the stock 7.1 kernel hangs on the trial device
trees. The header also says how to recover from macOS if Linux no longer boots.

`magicmouse.sh` builds the Magic Mouse patch as a module against the running kernel's source and
moves the mice and trackpads over to it, without a reboot; `magicmouse.sh undo` gives them back
to the kernel's driver.
`applekbd.sh` does the same for the keyboard patch, in the same tree (`build` after
`magicmouse.sh build`, then `try`, `undo`).

## Tools

- `tbt-capture.sh`: records enclosure plug-ins with driver debugging on, for reports.
- `boot-dump.sh`: what the running kernel brought up, into one file, to compare kernels.
- `apciec-dump.sh`: run in macOS: the tunneled PCIe controller's registers and device tree
  there, the reference for the Linux driver.

## License

GPL-2.0-only (`LICENSE`), the kernel's: the patches change its files, and the scripts that build and
try them go with them.
