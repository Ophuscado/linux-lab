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

## No backport to 7.1
Between `asahi-7.1.13-3` and the trial tree 30 files differ under `drivers/thunderbolt` and 34 under `drivers/usb/typec`, with interface changes across unrelated drivers. Decision: develop on the pinned 7.2 tree, daily use on the stock kernel, move when the GPU driver is re-enabled upstream. 2026-10-11.

## Asahi does not take LLM work
Policy read 2026-10-11: generative AI is forbidden for material contributions; LLM-drafted issues may be closed; using an LLM on m1n1 hypervisor traces is listed as a violation; concealment leads to a ban. Decision: publish in this repository and the operator's fork, always disclosed. Any report to Asahi is written by the operator.
