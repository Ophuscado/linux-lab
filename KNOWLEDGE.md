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
- [Why the GPU driver is off on the 7.2 tree](#why-the-gpu-driver-is-off-on-the-72-tree)
- [The 7.1 backport](#the-71-backport)
- [Pushing to a kernel fork from a shallow clone](#pushing-to-a-kernel-fork-from-a-shallow-clone)
- [Kernel and device trees must be switched together](#kernel-and-device-trees-must-be-switched-together)
- [What is inside the enclosure](#what-is-inside-the-enclosure)
- [No backport to 7.1](#no-backport-to-71)
- [Asahi does not take LLM work](#asahi-does-not-take-llm-work)
- [Vulkan against Metal for llama.cpp: public figures](#vulkan-against-metal-for-llamacpp-public-figures)
- [The 7.1 kernel on the Mac: results and the read ceiling](#the-71-kernel-on-the-mac-results-and-the-read-ceiling)
- [llama.cpp on the Mac: first numbers and where the time goes](#llamacpp-on-the-mac-first-numbers-and-where-the-time-goes)
- [The cooperative-matrix Mesa series](#the-cooperative-matrix-mesa-series)
- [Idle power and what the enclosure adds](#idle-power-and-what-the-enclosure-adds)
- [The fresh install, and four enclosures at boot](#the-fresh-install-and-four-enclosures-at-boot)
- [Filesystems for the migration](#filesystems-for-the-migration)
- [Two of four enclosures never get a tunnel: boltd and shared UUIDs](#two-of-four-enclosures-never-get-a-tunnel-boltd-and-shared-uuids)
- [All 32 disks at boot; what the inventory showed](#all-32-disks-at-boot-what-the-inventory-showed)
- [The migration plan and its safety rules](#the-migration-plan-and-its-safety-rules)
- [Sizes when installing again](#sizes-when-installing-again)
- [What macOS the m1n1 hypervisor wants](#what-macos-the-m1n1-hypervisor-wants)

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

## Why the GPU driver is off on the 7.2 tree
Probed 2026-10-11 by building `drivers/gpu/drm/asahi` on `tbt/pcie` with `depends on BROKEN` removed (rustc 1.97, bindgen 0.73.2, clang 18, 16K pages). The kernel crate builds; the driver stops in its first compile pass with 56 errors in nine files. They are API changes of the Rust kernel crate in 7.2, not typos: the GPUVM abstraction was replaced (`DriverGpuVm` now wants `Object`, `VaData`, `VmBoData`, `SmContext`, `sm_step_map/unmap/remap`; `UpdatingGpuVm`, `GpuVaFlags`, `OpUnMap`, `OpReMap`, `DriverGpuVmBo` are gone), which hits `mmu.rs`, the GPU's address-space code; the DRM driver trait changed (`FEATURES` gone, `RegistrationData`, `ParentDevice`, `Data` required); `kernel::iosys_map` and `shmem::SGTable` moved; and one macro change gives `u8: Deref` errors at eight firmware-structure sites. Later compile passes will add more. Upstream state the same day: `asahi-wip-7.2` unchanged since 2026-08-31, `bits/210-gpu` ends in the commit that marks the driver broken, no `asahi-7.2` tag, `asahi-wip` is still 7.1.13. Decision: do not port the GPU driver here; it is a rewrite of memory-management code that cannot be tested from the sandbox, and Asahi is doing it. For a kernel with both GPU and Thunderbolt disks, backport the USB4 stack instead: on top of v7.2 it is about 30 commits (`bits/270-thunderbolt` 21 plus the CIO reset driver, the Thunderbolt-switch part of `bits/260-spmi-typec` 4, `bits/170-atc` 3, device trees) plus this lab's 9, onto tag `asahi-7.1.13-3`, the source of the stock Fedora kernel. This replaces the earlier "No backport to 7.1" decision, which was made before the GPU mattered.

## The 7.1 backport
Built 2026-10-11 as branch `tbt/7.1` of the fork, on Asahi tag `asahi-7.1.13-3` (same commit as branch `asahi-wip`, the source of the stock Fedora kernel). What it took: cherry-picking Sven Peter's Thunderbolt commits fails at the first one, because 7.2 reworked the Thunderbolt core for non-PCI host interfaces, so `drivers/thunderbolt`, `include/linux/thunderbolt.h` and `drivers/net/thunderbolt` are taken whole from `tbt/pcie` (one include adapted: 7.2 split `mod_devicetable.h`). `tipd` (92 added, 31 removed lines apart) and `phy/apple/atc.c` (120/82) are taken whole too; the CIO reset driver, the Type-C Thunderbolt switch and the lab's PCIe and IOMMU commits are cherry-picked, the IOMMU one with a small conflict (7.1 derives the address mask from the table levels). Device trees are the trap: 7.2 moved every DART's DMA window from `apple,dma-range` into five-cell `iommus`, which is exactly what crashes the 7.1 display driver, so only the USB4 and PCIe hunks are taken and the NHI DARTs are written in 7.1 form (one cell plus `apple,dma-range`). Because the display nodes are untouched, the stock kernel should now tolerate these device trees; not tried. Checked in the sandbox: full build without warnings, all device trees build, and the script's build stage on a tree prepared like the operator's. Not run on the Mac.

## Pushing to a kernel fork from a shallow clone
GitHub answers "have" for commits of the whole fork network, so with `push.negotiate=true` a branch based on an Asahi commit was pushed to a fork that only had `master` at v6.14-rc3, from a depth-1 clone, as a pack of just the new commits (2026-10-11). Creating the ref through the API is not possible from the assistant's sandbox.

## Kernel and device trees must be switched together
Operator report, 2026-10-11: the stock 7.1.13 kernel, booted while the trial kernel's device trees were installed, hung and did not detect a USB keyboard; the trial kernel on the same device trees was fine. The device trees are part of `m1n1/boot.bin` (built by `update-m1n1` from whatever `/boot/dtb` points at), so there is one set per boot, not one per GRUB entry, and a raw dtb loaded by GRUB would miss m1n1's fix-ups. Fedora's `10-devicetree.install` assumes a newer device tree is always safe for an older kernel; that does not hold between Asahi 7.1 and `asahi-wip-7.2`. Cause, from the journal of the hung boot (it ran on the first trial device trees, before the PCIe nodes existed): the stock display driver logs `apple-dcp 2289c00000.dcp: ... Failed to created PIODMA iommu child device` and then dereferences NULL in `apple_rtkit_start_ep` from `dcp_start`, so the graphical boot never comes up. Decision: `tbt-kernel.sh try` and `stock` switch the default kernel and the device trees together and there is no one-shot boot any more; `install` leaves whichever of the two was active.

## What is inside the enclosure
macOS, 2026-10-11: root port, then ASMedia `1b21:2463` upstream and downstream bridges, then one Realtek `10ec:9100` AHCI controller (class 010601) with eight 18 TB SATA disks. So Linux needs nothing beyond the PCIe host: the stock `ahci` driver covers the rest.

## No backport to 7.1
Superseded on 2026-10-11 by [The 7.1 backport](#the-71-backport): the GPU driver is missing on 7.2, which changed the weighing.

## Asahi does not take LLM work
Policy read 2026-10-11: generative AI is forbidden for material contributions; LLM-drafted issues may be closed; using an LLM on m1n1 hypervisor traces is listed as a violation; concealment leads to a ban. Decision: publish in this repository and the operator's fork, always disclosed. Any report to Asahi is written by the operator.

## Vulkan against Metal for llama.cpp: public figures
Read 2026-10-11; none of it measured here yet. llama.cpp's Vulkan scoreboard (discussion 10879, Llama 2 7B Q4_0) lists an M2 Ultra on Asahi at 206 tokens/s for a 512-token prompt and 34 generating; its Metal table (discussion 4167) lists the M2 Ultra with 76 GPU cores at 1238 and 94 in 2023 and 1489 and 125 in August 2026 with flash attention. So the published gap is about six times on prompts and three on generation, on the same hardware. Both halves of the Vulkan path are userspace: the kernel driver only submits work and manages memory, while the shader compiler is Mesa's Honeykrisp and the shaders are llama.cpp's. llama.cpp at `c83f305` has no settings for Apple GPUs beyond one matrix-shader size choice for Honeykrisp (`ggml-vulkan.cpp`, "Honeykrisp driver for Asahi Linux doesn't report VK_VENDOR_ID_APPLE"), reports `matrix cores: none` on it, and can time each operation with `GGML_VK_PERF_LOGGER`. Issue 10982 (opened by an Asahi GPU developer, M2 Max: Metal 580 and 61, Vulkan 92 and 22 on Mistral 7B Q4_K_M) names the missing cooperative-matrix path and Mesa's code generation as causes. A third-party Mesa series (omacom/mesa pull requests 3 to 6, September 2026, not submitted upstream) adds `VK_KHR_cooperative_matrix` to Honeykrisp; its author restricts it to M1 until other chips pass an output check, and one outside run on an M2 Pro reports 14 to 80 percent more decode speed with one output differing from stock. Unverified claims, to be tested with an output comparison before any trust.

## The 7.1 kernel on the Mac: results and the read ceiling
Operator's boot dump, capture and bench of 2026-10-11, kernel `7.1.13-tbtwip` (`tbt/7.1` at `9d460b403164`). Verified: the GPU driver binds (`Initialized asahi 0.0.0`, G14D, 76 active cores), no deferred devices, no failed units, six controllers with their tuning data on all six ports. Plug-in: link up 1.1 s after the cable, eight disks about 22 s later (spin-up, `softreset failed (device not ready)` meanwhile is normal). Eject, unplug, replug: `Tunnel error`, `stopping tunnel`, `failed to stop engine (-19)`, then a clean second enumeration with eight disks; no IOMMU fault in either round.

Reads with `dd` and direct I/O, 4 GiB each: one disk at a time 267 to 287 MB/s (the platters), all eight together 211 MB/s each, 1.69 GB/s in total. The ceiling is inside the enclosure: its SATA controller's PCIe link is 8 GT/s x2 (its maximum, `LnkCap` and `LnkSta` agree), about 1.97 GB/s before packet overhead, while the USB4 link carries 2 x 20 Gb/s. Nothing on the Mac side limits sequential reads.

One new warning at boot, `WARNING: drivers/base/core.c:1504 at __device_links_no_driver`, for `2702280000.usb` (same device pointer as the "late IOMMU probe" warning two lines earlier): the USB controller's probe was deferred while the `apple_dart` module was still probing the IOMMU that had just attached to it. The port works afterwards (the keyboard is on it). Inferred to be a timing variant of the "late IOMMU probe" warning the stock kernel also prints; not seen in three 7.2 boots, and no clean stock boot dump exists yet to compare.

## llama.cpp on the Mac: first numbers and where the time goes
Operator's run of 2026-10-11: kernel `7.1.13-tbtwip`, Mesa 26.2.4 (Honeykrisp, `Apple M2 Ultra (G14D B1)`), llama.cpp `f2cc7282`, model `gpt-oss-20b-Q4_0.gguf` (10.7 GiB, mixture of experts, expert weights in MXFP4). Tokens per second:

| | 512-token prompt | generating 128 |
|---|---|---|
| CPU, 16 performance cores | 237 | 64.8 |
| Vulkan, all layers | 617 | 35.8 |

Flash attention changes neither. So today the GPU wins on prompts by 2.6 times and loses on generation by 1.8 times; for this model, generation is best left on the CPU (`-ngl 0`). llama.cpp reports for the device `fp16: 1`, `int dot: 0`, `matrix cores: none`.

Where the Vulkan time goes (llama.cpp's own per-operation timer; it submits each operation alone, so a token costs 35.9 ms there against 27.9 ms in the plain run). Generation, per token: expert mat-vec in MXFP4 (`MUL_MAT_ID_VEC`, 72 calls of about 245 us) 49 %; Q4_0 mat-vec (three shapes) 18 %; RMS norm 6 %; the output projection in Q8_0 4 %; attention 4 %. About 410 operations make a token and none averages under 28 us, even a row copy. Prompt: expert mat-mat in MXFP4 (`MUL_MAT_ID`) 67 %, Q4_0 mat-mat 21 %. Mat-mat runs at 4100 to 5700 GFLOPS; mat-vec at about 270 to 320, which is 70 to 90 GB of weights read per second in the large calls. A token reads about 2.2 GB of weights (from the call counts and shapes), so the plain runs correspond to about 80 GB/s on the GPU and 145 GB/s on the CPU. Inferred from that: generation is limited by how the mat-vec shaders walk memory on this GPU, not by arithmetic, so the first lever is llama.cpp's mat-vec settings (rows per work group, work-group size, integer path), which the Asahi driver gets as generic defaults. `llama-sweep.sh` measures them. Cooperative matrices only touch mat-mat, the prompt side.

Not known yet: the Metal figures for the same model and commit on this Mac.

## The cooperative-matrix Mesa series
Read 2026-10-11 at `omacom/mesa` pull request 6 head `795ae42a71c8` (includes 3 to 5): 56 commits by one author on upstream main `7cda7850edd1` (26.3 development), touching the asahi driver, nir, spirv, the Vulkan runtime and tests; build files only gain sources. It exposes `VK_KHR_cooperative_matrix` through hardware matrix instructions (`simd_matrix_fmadd16/32`, 8x8x8, tiled to 16x16x16) and changes compute batching. Chip classes: any generation-14 GPU with more than one cluster is `AGX_CHIP_G14X`, which includes the M2 Ultra (8 clusters), and the series enables cooperative matrices there by default since `5fbd5e9` (author's claim on an M2 Max: prompt 160 to 902 tokens/s, same output); `AGX_SIMDMAT=0` turns them off. llama.cpp accepts cooperative matrices from this driver without an allow-list and uses them for mat-mat only. The driver alone (`-Dvulkan-drivers=asahi`, no OpenGL or window system) configures and builds from that commit with LLVM 20 on x86-64 in the sandbox; it installs one library and an ICD file with an absolute path, so `VK_DRIVER_FILES` is enough to use it beside the system Mesa. Not run on the GPU yet.

## Idle power and what the enclosure adds
Operator's power dumps of 2026-10-11, kernel `7.1.13-tbtwip`, `tuned` profile balanced, sensor `macsmc_hwmon` "Total System Power", two readings ten seconds apart each: 20.8 and 21.1 W with nothing attached; 27.5 and 27.4 W with the enclosure attached and its disks idle (the enclosure has its own supply, so this is the Mac's side only). In that state the PCIe links have ASPM L1 on and L1 substates off, the SATA links are at `med_power_with_dipm`, and the USB4 link stays in CL0: the log says `CLx: CL0s/CL1 supported` for one end and `not supported` for the other. With nothing attached, all six Thunderbolt PCIe controllers still hold their power domains (`atcN_pcie` on, `runtime=unsupported`) while their root ports are runtime-suspended; what that costs is unknown until the same reading is taken on the stock kernel. Disk queues: `bfq`, 8 MiB read-ahead, depth 32; since sequential reads already sit at the enclosure's link ceiling, nothing there is worth changing. `hdparm -C` says `unknown` for the Seagate disks and `idle` for the Toshiba ones (inferred: the Seagates are in one of their intermediate idle states, which `smartctl -n standby` names). `asahi-btsync.service` does not exist on this system, so nothing has been copying macOS Bluetooth pairings at boot.

## Sizes when installing again
2026-10-13. The 4.0 TB disk held macOS at 1.0 TB and a Linux root of 3.0 TB, which Linux shows as 2.7T (binary units); nothing was lost. Read in the installer's source (`asahi-installer` `main.py`, `util.py`): the resize prompt asks for the new size of the macOS partition, not of Linux; `GB` and `TB` are decimal, `GiB` binary, a bare number is bytes; it keeps 38 GB free in macOS and takes 2.5 GB for its boot stub; "New OS size" defaults to `max`. Around the root the installer adds the stub, a 500 MiB EFI partition and a 1 GiB `/boot`; the system container (0.5 GB) and recovery (5.4 GB) stay. Standing decision of the operator: the Linux root gets 3.5 TB, everything else shares the rest (about 490 GB for macOS). `reinstall-prep.sh` computes the macOS size from the partition offsets. Partitions are deleted with `diskutil eraseVolume free free` and `diskutil apfs deleteContainer` (Asahi's partitioning cheatsheet), never with Disk Utility, and never the recovery partition.

## What macOS the m1n1 hypervisor wants
Asahi's hypervisor guide, read 2026-10-13: supported guests are macOS 13.5 (M1 and M2 series) and 14.8.3 (M1 to M3); other versions are explicitly not supported and 15 or later is not mentioned. The guest is a second macOS on its own volume inside the existing macOS container ("Create a second Volume on your macOS partition"), not a partition of its own, so it needs no room in the partition table. Only when tracing starts is that volume's security lowered from recovery (`bputil -nkcas`, `csrutil disable`) and m1n1 installed as its boot object with `kmutil configure-boot`; a host computer on the DFU port drives it. A Kernel Debug Kit is optional. 13.5 is also the firmware version Linux runs here (`os-fw-version: 13.5` in the boot dumps), so a 13.5 guest talks to the same firmware interfaces. Whether the M2 Ultra itself has been run under the hypervisor is not stated there. Getting the installer, 2026-10-13: `softwareupdate` on the operator's Mac offers neither 13.5 nor 14.8.3 (only 14.8.7 to 14.8.9 of that line), and Apple's own package URL for 13.5 (22G74) answers 403. The guide's fallback is an archived `InstallAssistant.pkg` (archive.org items `install-assistant_20240930` for 13.5, `install-assistant_20250207` for 14.8.3); being a third-party copy, its Apple signature is checked with `pkgutil --check-signature` before it is run.

## The fresh install, and four enclosures at boot
Operator, 2026-10-14: Fedora Asahi reinstalled on a larger partition (Linux now has 3.5 TB of the SSD), `setup.sh` brought it to the lab state, the restore rehearsal passed (a restore leaves its `before-restore-<time>` snapshot for an undo and `cleanup` deletes the replaced `root.replaced-<time>` subvolume: both as designed). The system keeps a macOS 13.5 volume for hypervisor tracing. Their `bt-sync.sh` fix (38cc6a8): on this Mac `asahi-btsync list` prints a format the old parser did not match, so stale entries were never replaced.

Status of 2026-10-14 with four enclosures attached at boot, disks powered off: the two on ports 2 and 3 hold PCIe tunnels (domains 000a and 000b, SATA controller present, nine ports each with no link); the two on ports 0 and 1 lost their USB4 link 9 s after the first PCIe controller came up (`Gen2/3 link error`, `SBX disconnected`) and came back as USB mass storage (`174c:2463` on `uas`, no medium). Inferred: the known 10-second rule, the tunnel of those two was activated before their PCIe controller was ready, and nothing retries. A replug of those two gives them a tunnel; the backlog line about retrying is the real fix. There are 4 enclosures x 8 disks of 18 TB: 32 disks, one 4.5 TB WD disk on USB.

## Filesystems for the migration
Decision 2026-10-14 (default, operator to confirm): XFS on all 32 disks. The parity disks force it: SnapRAID keeps each parity level in one file (or a list of files), and an 18 TB disk's parity file is about 16.4 TiB, over ext4's 16 TiB limit for one file at 4 KiB blocks; XFS allows 8 EiB. Data disks could be ext4, but one filesystem across the set means one set of tools, one `fstab` pattern and no accidental limit later. XFS cannot shrink and has no undelete, neither of which matters for a disk that is filled once and kept. Mount with `noatime`; SnapRAID itself needs no special options. Inferred, not yet measured: large-file writes over the enclosure link will run at the disk's 250 to 290 MB/s, so a full 16 TB copy is about 18 hours, and a row's seven copies in sequence are about five days; the four rows are independent and run in parallel.

## Two of four enclosures never get a tunnel: boltd and shared UUIDs
Operator's bolt log and captures, 2026-10-14. With four ASM2464 enclosures, two always came up and two always fell back to USB, at boot and after replugs, on changing ports. The domain runs at `security=user`, so a device gets its PCIe tunnel only once authorized, and that is boltd's job. boltd's store holds exactly two device UUIDs (`0e3a4c17-c007…`, `1a524c17-2032…`) for four boxes: the ASMedia firmware does not give each box a unique router UUID. When a box whose UUID is already connected appears, boltd re-points its record (`authorized -> connected`) and never authorizes it; the box gets no tunnel and drops the USB4 link after 10 s. Verified by the log; the earlier "tunnel before driver" reading was wrong, it was always this. Fix: a udev rule that writes `authorized=1` on every new thunderbolt device (`tbt-kernel.sh authorize on`, installed by `install`), which makes boltd irrelevant; the kernel keeps devices by route, so same UUIDs in different domains are fine. Consequence for the board: the "retry when the tunnel precedes the driver" line is withdrawn.

## All 32 disks at boot; what the inventory showed
Operator, 2026-10-14, after `authorize on` and one reboot with the four boxes attached: four tunnels, 32 SATA disks, no fallback to USB. Verified fix. Findings from the inventory and boot log:
- Bays are not SATA ports: two boxes wire their eight bays to ports 0 to 5, 7 and 8, so "slot" is not the bay and names must come from the HFS+ labels (`HD_nn`) or from the operator. The labels found give the row of each box: domain 0008 holds 24 to 31, 0009 holds 00 to 07, 000a holds 08 to 15, 000b holds 16 to 23. 20 of 32 disks have no label.
- Box 0008 (24 to 31) has a different SATA controller, `20c3:3118`, not the Realtek `10ec:9100` of the other three; its disk on port 3 (`sdad`, WDC, full) logged four `BadCRC` link errors in the first 20 s and was dropped to 3.0 Gb/s by the kernel. A CRC error on the SATA link is the cable or the backplane contact, not the platters; reseat that disk before any copy, and that box's bays are suspect for the whole migration.
- Fill: 18 disks within 1.6 TB of full, 4 nearly empty (the old parity disks), the rest between 1.7 and 13.3 TB.

## The migration plan and its safety rules
Decided 2026-10-14 with the operator's full inventory (all 32 named by label). Per row, content moves one bay down, so names stay with bays and the first bay (00, 08, 16, 24) ends empty for parity: A `30>31 … 24>25`, B `06>07 … 00>01`, C `14>15 … 08>09`, D `22>23 … 16>17`. Sequential within a row (two disks busy, six free to spin down), rows in parallel. `migrate-row.sh` formats a disk only if it is under 1 GB used and confirmed by typing its name, or if the script itself verified its copy on the next disk; the copy is `rsync -aHAX` with retries, then a full checksum read-back (`VERIFY=quick` for size and time only); any difference stops the row with the source untouched; state in `~/migrate/state`, resumable. The read-only udev rule had to change for this: a whole disk flagged read-only blocks writes to any partition on it, so the rule now flags HFS+ partitions only (`99-tbt-readonly.rules`, after udev's blkid import). Checked on loop devices with ext4 standing in for HFS+: three-step chain, owners, hard links, xattrs and names kept, re-run a no-op, data-bearing target refused, differing trees caught. Symbolic links get the copy's time. Not run on the Mac. Old parity disk 31 still holds about 100 GB and will be refused until emptied.
