# Knowledge

Costly discoveries and standing decisions. Each entry carries its evidence and date;
recheck before relying on one for anything consequential.

- [Stock kernel has no Apple USB4 host](#stock-kernel-has-no-apple-usb4-host)
- [Trial tree and its limits](#trial-tree-and-its-limits)
- [Cable speed 4 broke link training](#cable-speed-4-broke-link-training)
- [The enclosure only tunnels PCIe](#the-enclosure-only-tunnels-pcie)
- [Fallback to USB 3 needs a role cycle](#fallback-to-usb-3-needs-a-role-cycle)
- [m1n1 1.6.1 is enough for now](#m1n1-161-is-enough-for-now)
- [Boot chain on Fedora Asahi](#boot-chain-on-fedora-asahi)
- [The internal PCIe driver already names tunnel registers](#the-internal-pcie-driver-already-names-tunnel-registers)
- [Trial kernel boots clean](#trial-kernel-boots-clean)
- [The Thunderbolt PCIe controller is a sibling of the internal one](#the-thunderbolt-pcie-controller-is-a-sibling-of-the-internal-one)
- [A 2023 driver for the tunneled controller exists](#a-2023-driver-for-the-tunneled-controller-exists)
- [Where the PCIe tunables go](#where-the-pcie-tunables-go)
- [Power gates of the tunneled controller](#power-gates-of-the-tunneled-controller)
- [First runs of the PCIe tunnel port](#first-runs-of-the-pcie-tunnel-port)
- [The tunneled port offsets DMA addresses](#the-tunneled-port-offsets-dma-addresses)
- [Disks work; what eject and replug do](#disks-work-what-eject-and-replug-do)
- [Pushing to a kernel fork from a shallow clone](#pushing-to-a-kernel-fork-from-a-shallow-clone)
- [Kernel and device trees must be switched together](#kernel-and-device-trees-must-be-switched-together)
- [What is inside the enclosure](#what-is-inside-the-enclosure)
- [No backport to 7.1](#no-backport-to-71)
- [Asahi does not take LLM work](#asahi-does-not-take-llm-work)

## Stock kernel has no Apple USB4 host
7.1.13-402.asahi.fc44: `CONFIG_USB4=y` is the PCI driver only; no Apple code under `drivers/thunderbolt`, no USB4 device-tree nodes (source at tag `asahi-7.1.13-3`). A USB4 partner leaves the port at USB2: `ATCPHY_PIPEHANDLER_STATE_USB4 not implemented; falling back to USB2`. 2026-10-11.

## Trial tree and its limits
`AsahiLinux/linux` branch `asahi-wip-7.2` at `236788cd2602` (7.2.2) has `drivers/thunderbolt/apple.c` (`CONFIG_USB4_APPLE_SOC`, needs `CONFIG_RESET_APPLE_CIO`) and USB4 nodes for all six ports of t6022-j475d. The GPU driver is `depends on BROKEN` there (commit `97b22d135`), so the desktop renders on the CPU. Only XDomain and USB3 tunnels are implemented; no PCIe host. 2026-10-11.

## Cable speed 4 broke link training
The cables report Enter_USB cable speed 4 (eudo `0x2687e000`). The driver set the 20 Gb/s flag only for speed 3, giving cable info `0x1`; firmware then logged `RT Broadcast LOCAL: gen=1` against `REMOTE: gen=2` and about 30 `Gen2/3 link error` lines a second. Forcing bit 4 (`0x11`): `LOCAL: gen=2`, both lanes `entered CL0`, `thunderbolt 0-1: ASMedia 246x`, 20 Gb/s dual lane. Both plug orientations. Capture 2026-10-11 13:08. Fix: `patches/0001`.

## The enclosure only tunnels PCIe
Its router (`174c:2463`) lists two lane adapters and one PCIe up adapter; kernel prints `TBT3 support: yes, xHCI: no`. Linux activates the PCIe tunnel (`PCIe Down/Up path activation complete`), nothing answers on the Mac side, and exactly 10.0 s later the enclosure drops the link (`SBX disconnected!`). It is an 8-disk unit: in USB mode it shows one removable disk with no medium (`Media removed`, 0 B). Capture 2026-10-11 13:08.

## Fallback to USB 3 needs a role cycle
After the drop the port controller reports `USB3_CONNECTION|USB3_GEN2` without a disconnect. The host role stayed active, the PHY changed mode under a running controller and the device came up at 480M. With `patches/0002` the same enclosure sits at 10000M (observed final state, 2026-10-11 13:41; the transition itself was not captured).

## m1n1 1.6.1 is enough for now
The driver accepts the host DROM from 1.6.1. Diff 1.6.1..1.9.9 changes PHY tuning only for M3/M4. 1.9.9 adds a unique router ID per port; under 1.6.1 every router reports `009751a0-f8da-0100-ffff-ffffffffffff`. Fedora 44 ships 1.6.1; Fedora's 1.9.9 build is `m1n1-1.9.9-1.fc46` on Koji. 2026-10-11.

## Boot chain on Fedora Asahi
`kernel-install add` points `/boot/dtb` at the new kernel's device trees and runs `update-m1n1`, which rebuilds `m1n1/boot.bin` on the EFI partition from `/usr/lib64/m1n1/m1n1.bin`, those device trees and U-Boot. That file is shared by every kernel. Pristine copy: `m1n1/boot.bin.stock`, sha256 `6522d07f...e634e`, saved 2026-10-11 12:06 UTC. The EFI partition is mounted root-only; a second mount inherits that.

## The internal PCIe driver already names tunnel registers
`drivers/pci/controller/pcie-apple.c` (internal PCIe, `apple,t6020-pcie`) defines `PORT_TUNCTRL` (0x988: PERST_ON, PERST_ACK_REQ), `PORT_TUNSTAT` (0x98c) and interrupt bit 31 `PORT_INT_TUNNEL_ERR`, none of them used. m1n1 already copies tuning data for `/arm-io/apciec%d` into nodes aliased `usb4_%d_pcie`: `apple,tunable-debug`, `-fabric`, `-rc`, and `apple,tunable` on the first port subnode. Both point at the Thunderbolt PCIe controller being the same block as the internal one (inferred, to be confirmed against apciec.txt). 2026-10-11.

## Trial kernel boots clean
Boot dump of 7.2.2-tbtwip, 2026-10-11: no deferred devices, no failed units. Firmware: iBoot1 `mBoot-20457.1.29`, iBoot2 `iBoot-8422.141.2`, OS firmware 13.5, m1n1 stage 2 v1.6.1. Warnings present are not from this work: `dwc3-apple ... late IOMMU probe at driver bind` (also on stock), missing `apple/avd-fw-v3-t1.bin`, brcmfmac `-52` errors. Thunderbolt logs `device links to tunneled native ports are missing!`, which the PCIe work has to address.

## The Thunderbolt PCIe controller is a sibling of the internal one
From the macOS device tree (27.0.1, Mac14,14), read 2026-10-11. Six nodes `apciec0..5`, `compatible = "apciec,t6000"`, `device_type = "pci-c"`, macOS driver `AppleT6000PCIeC`, root port `106b:1014`. Per port, with B = 0x7, 0xb, 0xf, 0x13 (die 0) and 0x27, 0x2b (die 1) times 0x1_0000_0000:

| Region | Address | Size |
|---|---|---|
| config (ECAM) | B + 0x30000000 | 0x10000000 |
| rc | B + 0x20000000 | 0x4000 |
| fabric | B + 0x20004000 | 0x4000 |
| port | B + 0x21000000 | 0x8000 |
| IOMMU (`dart,t8110`, sid 0xf) | B + 0x21008000 | 0x4000 |
| debug (see the tunables entry) | B + 0x20200000 | 0x4000 |
| unidentified | B + 0x2100c000, B + 0x21010000 | 0x4000 each |

Port 0: interrupt 0x4f0, 32 MSIs from 0x729, MSI address 0xfffff000, power gates 0x234 and 0x3f, windows 64-bit prefetchable 0x8_0000_0000 (8 GB), 32-bit 0xa_0010_0000 (bus 0x100000, about 1 GB), 32-bit prefetchable 0xa_4000_0000 (1 GB). Each further port adds 0x12 to the interrupt, 0x20 to the MSI base and 1 and 2 to the power gates.

This is the layout `pcie-apple.c` already handles for the internal controller on t8103: rc, fabric at rc + 0x4000 (`CORE_FABRIC_STAT`, same 0x001f001f mask as the first fabric tuning entry), port at rc + 0x1000000, same MSI doorbell address. Decision: extend `pcie-apple.c` with a single-port tunnel variant instead of writing a new driver. Inferred, not yet run: the "rc" tuning offsets (0x78, 0x718, 0x814, 0x8bc) look like DesignWare root-port registers reached through config space.

## A 2023 driver for the tunneled controller exists
Found 2026-10-11 in `AsahiLinux/linux` branch `atcphy-20230219` (Sven Peter, M1): `pcie-apple.c` with an `apple,usb4-pcie` variant, `drivers/thunderbolt/protocol_adapter.c`, and node `pciec1` in `t8103.dtsi` at the same offsets as `apciec` here (config B + 0x30000000, rc B + 0x20000000, port B + 0x21000000, IOMMU B + 0x21008000). No later Asahi branch carries it (`sven/tbt-wip`, `bits/270-thunderbolt`, `b4/apple-soc-tbt`, `tbt-reset-wip`, `asahi-wip-7.2` checked: only the register names survive). m1n1 has filled in the matching tunables since February 2023, 1.6.1 included (aliases `usb4_N_pcie`, `usb4_N_pcie_adapter`). Decision: port that driver instead of working the sequences out again; branch `tbt/pcie` of the fork is the port. Its tunnel start is: release tunnel PERST (`PORT_TUNCTRL`), start the LTSSM, wait for link up, rescan the root port as a hotplug bridge, write 1 to `PORT_PREFMEM_ENABLE`. Its tunnel stop resets the whole controller through the `ATCn_PCIE` power state.

## Where the PCIe tunables go
From the macOS device tree and m1n1 source, 2026-10-11. `atc-apcie-fabric-tunables` go to rc + 0x4000 and `atc-apcie-debug-tunables` to B + 0x20200000 (the region the 2023 node covers with an rc size of 0x202000; this settles one of the three unidentified regions). `apcie-config-tunables` go to the port registers, as m1n1 does for the internal controller. `atc-apcie-rc-tunables` are applied to the root port's configuration space: inferred, because the list starts with the same entry (0x78, mask 0x7000) as the internal `pcie-rc-tunables`, which m1n1 applies there. The ACIO node's `pcie_adapter_regs_tunables` (one entry, 0x1008 |= 0x6) go to ACIO base + 0xe44000. `pcie_apple.tunnel_tunables=0` skips the PCIe ones if they turn out wrong.

## Power gates of the tunneled controller
From the macOS power manager table, 2026-10-11: `apciec0` gates 0x234 and 0x3f are `AUSB0_AONPCIE-V` (virtual, child of `ATC0_USB_AON`) and `ATC0_PCIE` (register 0x278, child of `ATC0_COMMON`), which Linux has as `ps_atc0_usb_aon` (always on) and `ps_atc0_pcie`. Ports 1 to 3 follow with 0x41, 0x43, 0x45; die 1 repeats the numbering.

## First runs of the PCIe tunnel port
Operator's boot dumps and captures, 2026-10-11, kernel `tbt/pcie` at `1b233c05d585`. Verified: all six controllers probe at boot without a cable (root ports `106b:1014`, domains 0008 to 000d, 64 RID/SID entries, so the T8103 register layout is right; `LINKSTS 0xa9000200`, `TUNSTAT 0x1` while idle); m1n1 1.6.1 fills in the tunables; the six IOMMUs probe after their controllers. With an enclosure on the port of `usb4_0`: `Link up` 13 ms after the PCIe paths, bridges `1b21:2463` on buses 1 and 2, AHCI `10ec:9100` (nine ports) on bus 3, MSI assigned, and the enclosure stays on USB4 instead of dropping after 10 s. Not working in that run: DMA (next entry), so no disks. Once, unplugging and plugging again froze the machine; nothing of that boot's log survived. The operator sees macOS panic on replug of the same enclosure too. `tbt-capture.sh` now flushes the kernel log line by line to a `.klog` file.

## The tunneled port offsets DMA addresses
Same run. The AHCI controller was given IOVAs just under 4 GB and the IOMMU reported `translation fault ... stream:1 code:0x2 (NO PGD FOR IOVA) at 0x100fffc0440`: the port adds 0x100_00000000 to the address a device uses. This matches macOS's `vm-base` of 0x100_80000000 for `dart-apciec`. Fix in `bf1b5bf89f` and `523466d61f0b`: `apple,dma-offset` on the IOMMU node makes the driver map at address plus offset, and `apple,dma-range` keeps device addresses below 4 GB. Whether addresses above 4 GB would also just be offset is not known, hence the limit. The internal PCIe IOMMUs have a `vm-base` with the same prefix in macOS yet work without an offset in Linux; not understood.

## Disks work; what eject and replug do
Operator's capture of 2026-10-11 17:04, kernel `tbt/pcie` at `523466d61f0b`. Verified: with the DMA offset no translation fault is logged, the AHCI controller brings up eight 18 TB disks at 6.0 Gb/s with NCQ, each with a 200 MB EFI partition and one HFS+ volume (not APFS; the APFS entries in `lsblk` are the internal SSD), all read-only through the udev rule. The USB4 link is 2 lanes at 20 Gb/s; the SATA controller's own PCIe link is 8 GT/s x2. The kernel's "2.000 Gb/s available PCIe bandwidth, limited by 2.5 GT/s PCIe x1 link" line describes the virtual link through the tunnel and is not a measured limit (inferred; `tbt-kernel.sh bench` measures).
Replug: after the PCI devices of the enclosure were removed through sysfs, the port controller reported a mode change (`set cable state: 0` then `2` within a millisecond), ACIO restarted, the PCIe link came up again and the AHCI controller re-enumerated by itself, at first with all SATA links down. Inferred: the ASM2464 reconnects when its PCIe side goes unused, like its 10 s USB4 fallback. So `eject` now removes only the disks (SCSI delete after sync) and leaves the controller bound. The physical unplug that followed, with `ahci` bound and no disks attached, went through cleanly: `Tunnel error`, `stopping tunnel`, `failed to stop engine (-19)` per port, controller reset, root port back, and the next plug brought everything up again. The one freeze happened in the run where DMA was broken and every port was in error handling; pulling an enclosure with disks attached and busy is still untested.

## Pushing to a kernel fork from a shallow clone
GitHub answers "have" for commits of the whole fork network, so with `push.negotiate=true` a branch based on an Asahi commit was pushed to a fork that only had `master` at v6.14-rc3, from a depth-1 clone, as a pack of just the new commits (2026-10-11). Creating the ref through the API is not possible from the assistant's sandbox.

## Kernel and device trees must be switched together
Operator report, 2026-10-11: the stock 7.1.13 kernel, booted while the trial kernel's device trees were installed, hung and did not detect a USB keyboard; the trial kernel on the same device trees was fine. The device trees are part of `m1n1/boot.bin` (built by `update-m1n1` from whatever `/boot/dtb` points at), so there is one set per boot, not one per GRUB entry, and a raw dtb loaded by GRUB would miss m1n1's fix-ups. Fedora's `10-devicetree.install` assumes a newer device tree is always safe for an older kernel; that does not hold between Asahi 7.1 and `asahi-wip-7.2`. Cause, from the journal of the hung boot (it ran on the first trial device trees, before the PCIe nodes existed): the stock display driver logs `apple-dcp 2289c00000.dcp: ... Failed to created PIODMA iommu child device` and then dereferences NULL in `apple_rtkit_start_ep` from `dcp_start`, so the graphical boot never comes up. Decision: `tbt-kernel.sh try` and `stock` switch the default kernel and the device trees together and there is no one-shot boot any more; `install` leaves whichever of the two was active.

## What is inside the enclosure
macOS, 2026-10-11: root port, then ASMedia `1b21:2463` upstream and downstream bridges, then one Realtek `10ec:9100` AHCI controller (class 010601) with eight 18 TB SATA disks. So Linux needs nothing beyond the PCIe host: the stock `ahci` driver covers the rest.

## No backport to 7.1
Between `asahi-7.1.13-3` and the trial tree 30 files differ under `drivers/thunderbolt` and 34 under `drivers/usb/typec`, with interface changes across unrelated drivers. Decision: develop on the pinned 7.2 tree, daily use on the stock kernel, move when the GPU driver is re-enabled upstream. 2026-10-11.

## Asahi does not take LLM work
Policy read 2026-10-11: generative AI is forbidden for material contributions; LLM-drafted issues may be closed; using an LLM on m1n1 hypervisor traces is listed as a violation; concealment leads to a ban. Decision: publish in this repository and the operator's fork, always disclosed. Any report to Asahi is written by the operator.
