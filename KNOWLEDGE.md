# Knowledge

Costly discoveries and standing decisions. Each entry carries its evidence and date;
recheck before relying on one for anything consequential.

- [Standing owner decisions](#standing-owner-decisions)
- [The kernel work lives in linux-patches](#the-kernel-work-lives-in-linux-patches)
- [Asahi does not take LLM work](#asahi-does-not-take-llm-work)
- [Vulkan against Metal for llama.cpp: public figures](#vulkan-against-metal-for-llamacpp-public-figures)
- [llama.cpp on the Mac: first numbers and where the time goes](#llamacpp-on-the-mac-first-numbers-and-where-the-time-goes)
- [The cooperative-matrix Mesa series](#the-cooperative-matrix-mesa-series)
- [Idle power and what the enclosure adds](#idle-power-and-what-the-enclosure-adds)
- [The fresh install, and four enclosures at boot](#the-fresh-install-and-four-enclosures-at-boot)
- [Filesystems for the migration](#filesystems-for-the-migration)
- [Two of four enclosures never get a tunnel: boltd and shared UUIDs](#two-of-four-enclosures-never-get-a-tunnel-boltd-and-shared-uuids)
- [All 32 disks at boot; what the inventory showed](#all-32-disks-at-boot-what-the-inventory-showed)
- [The migration plan and its safety rules](#the-migration-plan-and-its-safety-rules)
- [Sizes when installing again](#sizes-when-installing-again)
- [Final disk layout: pool and SnapRAID](#final-disk-layout-pool-and-snapraid)
- [SATA errors in the enclosures were a missing earth](#sata-errors-in-the-enclosures-were-a-missing-earth)
- [A global sync in a worker waits for every writer](#a-global-sync-in-a-worker-waits-for-every-writer)
- [rsync --no-inc-recursive copies nothing until the whole tree is listed](#rsync---no-inc-recursive-copies-nothing-until-the-whole-tree-is-listed)
- [Box C at 04:27 on 16 Oct, and every lost write since 14 Oct](#box-c-at-0427-on-16-oct-and-every-lost-write-since-14-oct)
- [Where the disks sit since 17 Oct](#where-the-disks-sit-since-17-oct)
- [The M424 24-bay box and this Mac](#the-m424-24-bay-box-and-this-mac)
- [The backup disk and the hangs in state D](#the-backup-disk-and-the-hangs-in-state-d)
- [HFS+ compression: files Linux reads as empty](#hfs-compression-files-linux-reads-as-empty)
- [Silent corruption and the sample check](#silent-corruption-and-the-sample-check)
- [System audit, 17 Oct](#system-audit-17-oct)
- [Desktop gaps on Plasma 6.7: what exists and what must be built](#desktop-gaps-on-plasma-67-what-exists-and-what-must-be-built)
- [kwin-solo-window is not absorbed](#kwin-solo-window-is-not-absorbed)
- [The TV's colour profile from oled-tv-calibrator](#the-tvs-colour-profile-from-oled-tv-calibrator)
- [smartd beside KDE's disk health monitor](#smartd-beside-kdes-disk-health-monitor)
- [Closing a window from the task switcher](#closing-a-window-from-the-task-switcher)
- [HackedSystem on Linux, as read on 18 Oct](#hackedsystem-on-linux-as-read-on-18-oct)
- [Where a generated token goes on Honeykrisp](#where-a-generated-token-goes-on-honeykrisp)
- [Metal, Vulkan through MoltenVK and Honeykrisp on this Mac](#metal-vulkan-through-moltenvk-and-honeykrisp-on-this-mac)
- [The ANE overlay panicked the boot: DART power island](#the-ane-overlay-panicked-the-boot-dart-power-island)
- Kernel work (from linux-patches, folded in on 2026-10-27):
  - [Standing owner decisions (kernel)](#standing-owner-decisions-kernel)
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
  - [Asahi does not take LLM work (kernel notes)](#asahi-does-not-take-llm-work-kernel-notes)
  - [The 7.1 kernel on the Mac: results and the read ceiling](#the-71-kernel-on-the-mac-results-and-the-read-ceiling)
  - [What macOS the m1n1 hypervisor wants](#what-macos-the-m1n1-hypervisor-wants)

## Standing owner decisions
Kept here so a resumed session does not re-ask them; each was stated by the owner.
- 2026-10-13: the Linux root gets 3.5 TB; see [Sizes when installing again](#sizes-when-installing-again).
- 2026-10-14: 07, 15, 23 and 31 (old parity, migrated before) and 04 (empty) hold nothing needed and were erased without a copy; one global pool, even spread; quick verify by size and time, not checksums; one read stream per box.
- 2026-10-14: the kernel stays as it is until the copies are done (agreed before the migration): a new kernel or a stock boot mid-migration puts the enclosures and the running copies at risk. Lines that need the stock kernel or a new one wait in the backlog.
- 2026-10-16: 15 stays in the pool unless it fails in operation (it did at 22:03, went out with `bad 15`, and came back on 17 Oct after `aside 15`).
- 2026-10-17, for the long run until the M424 boxes arrive: a big fan in front of all disks and air conditioning in the room; disks 13 and 15 swapped bays; the four parity disks (24, 00, 08, 16) moved into box C, so box C is read last (each row copies its parity disk last); resume every row with every branch, 15 included, one reader per row; spin-down after 10 idle minutes.
- 2026-10-17: two M424 boxes are bought to replace the home-made ones (returns are cheap; other boxes cost three times as much per 8 bays); see [The M424 24-bay box and this Mac](#the-m424-24-bay-box-and-this-mac).
- 2026-10-17: home backup with restic, as on the owner's servers (not borg): manual for now, later once an hour while the disk is connected, with a run lock; kept like Time Machine; up to 80 % of the disk; the password file is the owner's to write.
- 2026-10-17: eager mode wanted (verified disks join the pool soon, to spread writes and heat); restart rows on new script versions rather than leave old code running.
- 2026-10-17, how the lab takes in other people's work: built-in KDE features first (no launcher such as Vicinae); a thin layer over upstream rather than a fork; upstream projects kept as local clones pinned to a commit, updated on purpose; a fork only to absorb a small piece (kwin-solo-window is one) or to develop, as with the kernel. The default branch is master (GitHub and the claude remote).
- 2026-10-17, the look: the WhiteSur set (KDE, GTK, Firefox, icons, cursors) and only its WhiteSur variants; Apple's SF fonts used on this Mac despite their licence, with Inter beside them to compare; an Apple logo at boot for private use only; a GRUB theme taken from grub2-themes' WhiteSur without the rest; Kvantum undecided.
- 2026-10-17: every disk is trusted after a replug or a reboot ("consider all disks valid") until one fails; then the workers warn and stop, and `start` trusts them again. A file whose write failed is still set aside and copied again, which is about the data, not the disk.
- 2026-10-18: the KDE settings as the owner has them now are the desired defaults ("treat current diff as desired defaults"); system-diff.sh records them, and no script puts its own value over one of them without a switch the owner runs.
- 2026-10-18: Ctrl stays Ctrl, no Cmd-as-Ctrl swap: the owner moves their habits to Linux; the smoothing goes into Meta and Fn shortcuts.
- 2026-10-18: the TV keeps oled-tv-calibrator's Native HDR profile: colours less saturated than with KScreen's Built-in profile or none.
- 2026-10-18, the look: only WhiteSur and what KDE ships stay; everything else from KDE's store goes; theme.sh apply off returns to KDE's own look.
- 2026-10-18, calls home: off NetworkManager's connectivity check, the geoclue demo agent, Discover's notifier and the VM guest helpers; dnf countme stays; crash reports only after their review (ABRT auto-reporting off).
- 2026-10-18, programs: languages, debuggers, compilers and language servers may go in without asking when they are consolidated projects and not bloated; Flathub programs one by one after his review.
- 2026-10-18, windows: Konsole 1440x900, main programs 1366 (or 1280) wide; Fn+F maximize or restore, Fn+C centre, Fn+P keep above, Fn+D on all desktops.
- 2026-10-18, the projects: kernel changes are made to the standard of the kernel community (mainline style, professional), kept in their own repository; this repository is the Asahi, Fedora, KDE and Mac layer meant for anyone with this hardware after a plain Asahi install, kept as a parallel layer where upstream will not take it; HackedSystem gathers the daily administration, prototypes welcome; the migration stays private and ends.
- 2026-10-18: no log out while the migration runs (the owner); what needs a new login waits, or is applied live where Plasma allows (a plasmashell restart).
- 2026-10-18, giving back (the owner's "ok" to the rules proposed that day): a small, generic, tested fix goes upstream under the owner's name and the lab carries it until it lands, then drops it; taste and settings stay a local layer over an untouched upstream; a fork only as a patch series on a pinned upstream commit, each patch offered upstream; absorbing only small pieces of abandoned work, with their reference and licence; WhiteSur stays pinned clones plus theme.sh, its fixes carried as patches and sent to its author; Asahi excluded; each project's own rule on AI help followed (KDE: people are authors, no tool tags; the kernel: whatever applies when a patch is sent). First two: KWin's Thumbnail Grid and oled-tv-calibrator's Linux start.
- 2026-10-18, licences: "use common sense, best matching for this, inherit from parents when convenient" (the owner, after rejecting a closed-source section another agent had added: "this project is actually open-source"). linux-lab is GPL-2.0-or-later, as KDE whose pieces it carries; linux-patches is GPL-2.0-only, as the kernel. ansible's projects.py accepts an open licence named by SPDX id in README License with a LICENSE file.
- 2026-10-18, names Linux cannot read (an emoji, shown as ??) are expendable: "can be ignored if unrecoverable with a different name, not going to run macos now only for this ... do not interrupt workflow" (the owner). They are unrecoverable here: hfsplus turns each UTF-16 unit it cannot convert into '?' and then finds no entry of that name, and it has no export operations, so no open by handle either (fs/hfsplus at master, read 18 Oct). migrate-row.sh lists them in state/NN.unreadable and goes on; nothing is held for them. Those a git repository tracks come back after the verify from the copied .git (the index's blobs, under their real names: git keeps them in UTF-8), as the owner suggested for context7/, whose folders are all clones; the rest are lost with the source. The same day: more reader workers, given the stability; and the rsync leftover on hd-04 may go whenever it is safe (not in use, not recent).
- 2026-10-26: the kernel work stays a parallel branch on the owner's GitHub fork, disclosed; Asahi or anyone may
  cherry-pick it; a pull request to Asahi only by the owner, once they understand every line. linux-lab may become
  public later, after a check that nothing personal is in it; commits stay in their name. The home backup keeps
  project folders, builds and dependencies (work, not volatile), _run included (a database lives there); nothing under Projects or src is left out; ~/Projects/_llm is
  left out (its models live in the pool). SnapRAID: one array over every disk, 4 parity disks, growing to 6 at most.
- 2026-10-26, publishing: each public repository's master README is its showcase (what the branch work is, the
  measured results, links to the branches); work lives in branches, temporary work (the migration) included, so its
  facts stay readable after it ends; no profile repository. Docs neutral and impersonal, no "owner" wording, no
  line about AI assistance in the repositories. A submission to a project follows that project's own rules on tool
  use (the kernel's Documentation/process/coding-assistants.rst and generated-content.rst ask for transparency and
  a human Signed-off-by; Asahi forbids generative AI for material contributions).

## The kernel work lives in linux-patches
2026-10-18, the owner's project boundaries: the kernel patches, tbt-kernel.sh, tbt-capture.sh,
boot-dump.sh, apciec-dump.sh and magicmouse.sh moved with their history to the linux-patches
repository, and with them the findings on the USB4/Thunderbolt host, the tunneled PCIe ports,
the boot chain, m1n1 and the enclosure's insides (24 entries, its KNOWLEDGE.md). What
stays here is how this Mac uses the boxes: tbt-disks.sh (authorize, spin-down, eject, the
migration's read-only rule and mounts, bench).

## Asahi does not take LLM work
Policy read 2026-10-11: generative AI is forbidden for material contributions; LLM-drafted issues may be closed; using an LLM on m1n1 hypervisor traces is listed as a violation; concealment leads to a ban. Decision: publish in this repository and the owner's fork, always disclosed. Any report to Asahi is written by the owner.

## Vulkan against Metal for llama.cpp: public figures
Read 2026-10-11; none of it measured here yet. llama.cpp's Vulkan scoreboard (discussion 10879, Llama 2 7B Q4_0) lists an M2 Ultra on Asahi at 206 tokens/s for a 512-token prompt and 34 generating; its Metal table (discussion 4167) lists the M2 Ultra with 76 GPU cores at 1238 and 94 in 2023 and 1489 and 125 in August 2026 with flash attention. So the published gap is about six times on prompts and three on generation, on the same hardware. Both halves of the Vulkan path are userspace: the kernel driver only submits work and manages memory, while the shader compiler is Mesa's Honeykrisp and the shaders are llama.cpp's. llama.cpp at `c83f305` has no settings for Apple GPUs beyond one matrix-shader size choice for Honeykrisp (`ggml-vulkan.cpp`, "Honeykrisp driver for Asahi Linux doesn't report VK_VENDOR_ID_APPLE"), reports `matrix cores: none` on it, and can time each operation with `GGML_VK_PERF_LOGGER`. Issue 10982 (opened by an Asahi GPU developer, M2 Max: Metal 580 and 61, Vulkan 92 and 22 on Mistral 7B Q4_K_M) names the missing cooperative-matrix path and Mesa's code generation as causes. A third-party Mesa series (omacom/mesa pull requests 3 to 6, September 2026, not submitted upstream) adds `VK_KHR_cooperative_matrix` to Honeykrisp; its author restricts it to M1 until other chips pass an output check, and one outside run on an M2 Pro reports 14 to 80 percent more decode speed with one output differing from stock. Unverified claims, to be tested with an output comparison before any trust.

## llama.cpp on the Mac: first numbers and where the time goes
Owner's run of 2026-10-11: kernel `7.1.13-tbtwip`, Mesa 26.2.4 (Honeykrisp, `Apple M2 Ultra (G14D B1)`), llama.cpp `f2cc7282`, model `gpt-oss-20b-Q4_0.gguf` (10.7 GiB, mixture of experts, expert weights in MXFP4). Tokens per second:

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
Owner's power dumps of 2026-10-11, kernel `7.1.13-tbtwip`, `tuned` profile balanced, sensor `macsmc_hwmon` "Total System Power", two readings ten seconds apart each: 20.8 and 21.1 W with nothing attached; 27.5 and 27.4 W with the enclosure attached and its disks idle (the enclosure has its own supply, so this is the Mac's side only). In that state the PCIe links have ASPM L1 on and L1 substates off, the SATA links are at `med_power_with_dipm`, and the USB4 link stays in CL0: the log says `CLx: CL0s/CL1 supported` for one end and `not supported` for the other. With nothing attached, all six Thunderbolt PCIe controllers still hold their power domains (`atcN_pcie` on, `runtime=unsupported`) while their root ports are runtime-suspended; what that costs is unknown until the same reading is taken on the stock kernel. Disk queues: `bfq`, 8 MiB read-ahead, depth 32; since sequential reads already sit at the enclosure's link ceiling, nothing there is worth changing. `hdparm -C` says `unknown` for the Seagate disks and `idle` for the Toshiba ones (inferred: the Seagates are in one of their intermediate idle states, which `smartctl -n standby` names). `asahi-btsync.service` does not exist on this system, so nothing has been copying macOS Bluetooth pairings at boot.

## Sizes when installing again
2026-10-13. The 4.0 TB disk held macOS at 1.0 TB and a Linux root of 3.0 TB, which Linux shows as 2.7T (binary units); nothing was lost. Read in the installer's source (`asahi-installer` `main.py`, `util.py`): the resize prompt asks for the new size of the macOS partition, not of Linux; `GB` and `TB` are decimal, `GiB` binary, a bare number is bytes; it keeps 38 GB free in macOS and takes 2.5 GB for its boot stub; "New OS size" defaults to `max`. Around the root the installer adds the stub, a 500 MiB EFI partition and a 1 GiB `/boot`; the system container (0.5 GB) and recovery (5.4 GB) stay. Standing decision of the owner: the Linux root gets 3.5 TB, everything else shares the rest (about 490 GB for macOS). `reinstall-prep.sh` computes the macOS size from the partition offsets. Partitions are deleted with `diskutil eraseVolume free free` and `diskutil apfs deleteContainer` (Asahi's partitioning cheatsheet), never with Disk Utility, and never the recovery partition.

## The fresh install, and four enclosures at boot
Owner, 2026-10-14: Fedora Asahi reinstalled on a larger partition (Linux now has 3.5 TB of the SSD), `setup.sh` brought it to the lab state, the restore rehearsal passed (a restore leaves its `before-restore-<time>` snapshot for an undo and `cleanup` deletes the replaced `root.replaced-<time>` subvolume: both as designed). The system keeps a macOS 13.5 volume for hypervisor tracing. Their `bt-sync.sh` fix (38cc6a8): on this Mac `asahi-btsync list` prints a format the old parser did not match, so stale entries were never replaced.

Status of 2026-10-14 with four enclosures attached at boot, disks powered off: the two on ports 2 and 3 hold PCIe tunnels (domains 000a and 000b, SATA controller present, nine ports each with no link); the two on ports 0 and 1 lost their USB4 link 9 s after the first PCIe controller came up (`Gen2/3 link error`, `SBX disconnected`) and came back as USB mass storage (`174c:2463` on `uas`, no medium). Inferred: the known 10-second rule, the tunnel of those two was activated before their PCIe controller was ready, and nothing retries. A replug of those two gives them a tunnel; the backlog line about retrying is the real fix. There are 4 enclosures x 8 disks of 18 TB: 32 disks, one 4.5 TB WD disk on USB.

## Filesystems for the migration
Decision 2026-10-14 (default, owner to confirm): XFS on all 32 disks. The parity disks force it: SnapRAID keeps each parity level in one file (or a list of files), and an 18 TB disk's parity file is about 16.4 TiB, over ext4's 16 TiB limit for one file at 4 KiB blocks; XFS allows 8 EiB. Data disks could be ext4, but one filesystem across the set means one set of tools, one `fstab` pattern and no accidental limit later. XFS cannot shrink and has no undelete, neither of which matters for a disk that is filled once and kept. Mount with `noatime`; SnapRAID itself needs no special options. Inferred, not yet measured: large-file writes over the enclosure link will run at the disk's 250 to 290 MB/s, so a full 16 TB copy is about 18 hours, and a row's seven copies in sequence are about five days; the four rows are independent and run in parallel.

## Two of four enclosures never get a tunnel: boltd and shared UUIDs
Owner's bolt log and captures, 2026-10-14. With four ASM2464 enclosures, two always came up and two always fell back to USB, at boot and after replugs, on changing ports. The domain runs at `security=user`, so a device gets its PCIe tunnel only once authorized, and that is boltd's job. boltd's store holds exactly two device UUIDs (`0e3a4c17-c007…`, `1a524c17-2032…`) for four boxes: the ASMedia firmware does not give each box a unique router UUID. When a box whose UUID is already connected appears, boltd re-points its record (`authorized -> connected`) and never authorizes it; the box gets no tunnel and drops the USB4 link after 10 s. Verified by the log; the earlier "tunnel before driver" reading was wrong, it was always this. Fix: a udev rule that writes `authorized=1` on every new thunderbolt device (`tbt-kernel.sh authorize on`, installed by `install`; since 18 Oct `tbt-disks.sh authorize on`), which makes boltd irrelevant; the kernel keeps devices by route, so same UUIDs in different domains are fine. Consequence for the board: the "retry when the tunnel precedes the driver" line is withdrawn.

## All 32 disks at boot; what the inventory showed
Owner, 2026-10-14, after `authorize on` and one reboot with the four boxes attached: four tunnels, 32 SATA disks, no fallback to USB. Verified fix. Findings from the inventory and boot log:
- Bays are not SATA ports: two boxes wire their eight bays to ports 0 to 5, 7 and 8, so "slot" is not the bay and names must come from the HFS+ labels (`HD_nn`) or from the owner. The labels found give the row of each box: domain 0008 holds 24 to 31, 0009 holds 00 to 07, 000a holds 08 to 15, 000b holds 16 to 23. 20 of 32 disks have no label.
- Box 0008 (24 to 31) has a different SATA controller, `20c3:3118`, not the Realtek `10ec:9100` of the other three; its disk on port 3 (`sdad`, WDC, full) logged four `BadCRC` link errors in the first 20 s and was dropped to 3.0 Gb/s by the kernel. A CRC error on the SATA link is the cable or the backplane contact, not the platters; reseat that disk before any copy, and that box's bays are suspect for the whole migration.
- Fill: 18 disks within 1.6 TB of full, 4 nearly empty (the old parity disks), the rest between 1.7 and 13.3 TB.

## The migration plan and its safety rules
Decided 2026-10-14 with the owner's full inventory (all 32 identified by blinking), revised twice the same day: from a fixed chain, to a scheduler, to a pool, after the owner chose even distribution and confirmed that 07, 15, 23 and 31 may be erased. Per row: a mergerfs union of the bays this script has formatted to XFS (the parity bay 24/00/08/16 never joins), create policy most-free-space, `moveonenospc`, `minfreespace=4G`. Every HFS+ disk over 10 GB is a source, smallest first and the parity disk last (emptying it frees no bay); a source is copied into the pool with `rsync -aHAX --ignore-existing`, read back from the pool by checksum (`VERIFY=quick` for size and time), and only then may it be formatted and added as a branch (runtime, through the `user.mergerfs.branches` xattr). When all eight disks of a row hold data, the old parity disk is erased after a typed `erase nn`; disks under 10 GB (HFS+ metadata only) are formatted without asking. A same-path file from two sources is never overwritten: the second copy skips it and verification stops the worker with the path listed. Workers share a row through claim directories. Checked on eight loop disks with ext4 for HFS+ and real mergerfs: two workers, the erase prompt, all seven data sets present once in the pool with owners and hard links kept (mergerfs clones the parent path so a hard link lands on the source's branch), the parent folder `Library` merged, parity disk formatted last, rerun a no-op, a planted collision caught. Not run on the Mac. Distribution is not even at the end: bays join as they empty, so the last ones stay nearly empty; `mergerfs.balance` can even it out later at the cost of copying again. The read-only udev rule flags HFS+ partitions only, because a whole-disk flag would block writes to XFS partitions. Afterwards SnapRAID can protect all 28 data disks with the four parity disks as one four-parity array; the pools become the row mounts, or one mergerfs over all 28.

## Final disk layout: pool and SnapRAID

2026-10-15, owner decisions during the migration (28 Oct: data disks moved to /mnt/data/NN, mergerfs
minfreespace 900G so each 16.4 TB disk gives the pool 15.5 TB, noatime on the system disk). Data disks mount by label at /mnt/hd/NN,
parity disks (24, 00, 08, 16, one per box) at /mnt/parity/NN, the pool at /srv/pool as one
mergerfs over /mnt/hd/* (now /mnt/data/*) with category.create=pfrd (random, weighted by free space: parallel
writers spread over disks; mfs sent every stream to the single emptiest disk). SnapRAID with
4 parity levels over 28 data disks: SnapRAID's own table gives 4 for up to 28, the boxes
fail as a unit, data is ~360 TB of 504 TB raw so the 72 TB of parity cost nothing needed.
Content files on the root filesystem and on 25, 01, 09, 17. Apple xattrs (osx.*) were not
copied: the hfsplus driver lists them under truncated names it cannot read; owner: "file
flags are not very important since most things are ebooks". snapraid-setup.sh writes it all.
Evidence: loop-device run of snapraid-setup.sh: sync, scrub, a damaged file found by check
and repaired by fix.

## SATA errors in the enclosures were a missing earth

2026-10-15. Months of random SATA faults in the home-made boxes (BadCRC, Handshk, command
timeouts hopping between ports and boxes, under load, on macOS too; a bay "bad with any
disk"; box C dropping four ports under three readers) had one thing in common the logs could
not show: the USB-C plugs tingled and sparked. The Mac Studio ran on a two-pin EU cord through
a travel adapter, so its chassis floated; every box's PSU leakage then flowed through the
USB-C shields, the ground reference of every SATA pair. A three-pin cord for the Mac ended the
tingle at once. The error rate under load afterwards is the proof still to collect (OBSERVED
tingle gone; error counts INFERRED). Rule kept: Mac and boxes on one strip, three pins all
the way; `libata.force=3.0G` only if errors remain at 6 Gbps.

2026-10-16 update, OBSERVED: with the earth fixed and `libata.force=3.0G` on, four row workers
ran about two hours without a SATA error. Then hd-15 (box C) stopped answering at about 04:28
(rsync 11 on row C), IDENTIFY timeouts followed on ata34 and ata28 (04:43-04:46), and hd-15
still failed reads at 11:26. The earth was not the whole cause; heat or the supply under
sustained load are the next candidates, and the failing port is in the disk-plan by domain and
port.

The whole of box C, not one disk (kernel log, boot at 22:46:46 on 15 Oct). 04:27:01 ata32 (09)
resets; 04:27:20 all 32 queued writes to ata27 (15) time out; then every port of the box in
turn: the link comes up ("slow to respond", ready=0), the disk never answers IDENTIFY (5, 10,
30 s), the link drops to 1.5 Gbps, the port is disabled: ata27 04:28:46 (row C's rsync 11 at
04:28:56), then 31, 32, 30, 29, 35, 34, 28 until 04:46. libata handles the ports of one
controller one at a time, so a single event reads as a 17-minute cascade. The disks keep their
/dev names and fail every command (DID_BAD_TARGET). At 12:27 a rescan of the reseated 15 gave
the same: link up, never ready. OBSERVED. Ports: 15=ata27, 10=28, 08=29, 14=30, 13=31, 09=32,
12=34, 11=35 on this boot.

12:49, box C's supply power-cycled with its USB4 bridge left connected: the eight SATA ports
stayed (the controller kept power and its PCIe link; no reboot needed), all eight links came up
at once at 3.0 Gbps, every disk answered with an unknown signature (class 0), stayed not ready
through 45 s of IDENTIFY, and was detached. Yet the drives spun up, their LEDs and the fans were
on and the PSU looked healthy (the owner, OBSERVED): not the supply. What never reaches the
host is the first FIS ("softreset failed (1st FIS failed)") and the IDENTIFY data, which the AHCI
controller writes to memory by DMA: the controller or its DMA path through the tunnel is stuck,
the same for all eight ports, and a reboot resets it (INFERRED).

13:02, box C's PCI devices removed through sysfs (000a:01:00.0): this time the ASM2464 did not
come back by itself (unlike 11 Oct); a PCI rescan at 13:03 brought bridge and controller back
and ahci probed cleanly (9 ports, the empty port 6 link down), but the eight disks failed the
same way ("1st FIS failed", IDENTIFY timeouts). So neither a re-probe of the controller nor a
power cycle of the drives clears it; the one part never power-cycled is the bridge and SATA
controller, which stay powered from the Mac's port when the box's supply is cycled.

16 Oct, about 15:10 (kernel uptime 4670 s, boot 13:55): box C down again about an hour after the
workers restarted. ata27 (disk 15, port 0) cycles "SATA link down (SStatus 1)" every 2 s with
"EH pending after 5 tries, giving up"; the other seven disks of box C reject every command
(DID_BAD_TARGET). OBSERVED. Disk 15 is the common factor: at 04:27 the first failure was 32
queued writes to it timing out, now its port is the one that never links. As a pool branch it
takes about a fifth of all new files. INFERRED: disk 15 or its bay hangs box C's controller under
write load; boxes B and D run the same controller model without a fault.

Both failures ran with the disks' standby timer at 1, then 3 idle minutes (`tbt-kernel.sh
spindown`, all 32 disks; the owner, OBSERVED), and status showed most disks in standby
during the copy. The pool spreads new files over its branches, so each branch idles for minutes
and wakes again: many spin-ups an hour, each one the largest current a drive draws and seconds
in which it answers nothing. A weak power contact on 15 fails first at such a moment; the 32
writes to 15 that timed out at 04:27 fit a drive that did not come back. INFERRED. At the
18:11 restart the owner set the timer to 5 minutes (`spindown 5`; why not stated); if box C
falls over again, the timer goes off before anything else is changed.

About 15:41 (uptime 6387 s), with 15 reseated and box C's supply off: the eight SATA links went
down (SStatus 0), 2.6 s later the USB4 link ("SBX disconnected", "Tunnel error") and the box's
PCI devices went away, and 30 s later the link, the bridge and the controller came back by
themselves; seven disks attached within 25 s, without a reboot. OBSERVED. So bridge and
controller do lose power with the box's supply once it stays off a few seconds; at 12:49 it
was probably back on too soon (INFERRED). Port 0 (disk 15, ata36) still loops on "SATA link
down (SStatus 1)" on that freshly powered controller, at 1.5 Gbps too: the fault is in 15's
path, its data cable, its connector or the disk's interface, not a stuck controller. Link power
states are not involved: SControl 3x0 on every port has IPM 3, partial and slumber disallowed
(VERIFIED in the log).

16 Oct evening, disks 14 and 15 swapped bays and the Mac rebooted: disk 15 links in bay 3
(ata4), disk 14 never links in bay 0 (ata1, 1473 link errors within minutes); the other 31
disks show no link error. VERIFIED. The fault is bay 0 of box C (its data cable, the connector
in the bay, or controller port 0), not disk 15; it was the trigger of both box C failures.
Disk 15 holds only copies: no line of placement.txt lists it among the branches of a verified
source, and a source is formatted only after its verify, which reads the pool without 15.

17:46-17:55, after the owner swapped box C's internal data wires (which ones: UNKNOWN), box C
alone, `readtest C`: all eight disks link, disk 14 in bay 0 among them, each read at 210 MB/s
(1.68 GB/s in all, the box's ceiling) with no link error in 9 min. OBSERVED. The "wire swap"
was bay 0's cable moved to another port of the controller board (the owner; which port
UNKNOWN). So bay 0's link failure was the board's port 0 or the cable's seat in it (INFERRED);
the same kind of fault on another board port fits disk 15's write errors below.

18:15 disk 15 rejoined the pool in its new bay; from about 18:45 its port (ata16 on that boot)
had 11 link errors in the write direction: 32 queued 4 MiB writes frozen with SError
`{ RecovData Handshk }`, hard reset, link back at 3.0 Gbps, and after the second time libata
turned NCQ off on it ("NCQ disabled due to excessive errors"). Every reset recovered; no I/O
error reached the filesystem. Disk 13 (ata14, a source being read) had 2. OBSERVED. Reads of
15 were clean in the read test, so the fault shows when the host sends: disk 15's SATA
receiver or connector, or the wire now on its bay (INFERRED). Standing owner decision (16 Oct):
15 stays in the pool unless it fails in operation; the workers drop a branch that stops taking
writes (heal), and a short copy it leaves fails its source's verify.
After libata turned NCQ off on 15 (second burst, about 18:46) the owner saw no further link
error for 20 minutes. OBSERVED. One command at a time instead of 32 queued 4 MiB writes puts
less continuous traffic on a marginal link (INFERRED). The flag lasts until the disk is probed
again (a reboot), when NCQ comes back.
21:13:08 (uptime 11030 s) both box C ports with a working disk under load reset in the same
millisecond: ata16 (15, a single write without NCQ, `RecovData Handshk`) and ata14 (13, queued
reads, SError 0). OBSERVED. Two ports at once points at something they share, the controller or
the box's supply, more than at disk 15 alone (INFERRED).

16 Oct night, OBSERVED (journal, runs 2400 and 2421 on the panel): after `good 15` at 18:15
and NCQ off, ata14 (disk 13, a source being read) and ata16 (disk 15, a pool branch being
written) fail together: 18:46-18:49, 21:13 in the same millisecond, 22:02-22:03 again, then
five WRITE I/O errors on 15 and 337 READ errors on 13 until 22:07, and at 22:29 all eight
disks of box C answer every command with DID_BAD_TARGET. Boxes A, B and D log nothing. Two
bays failing at the same instant point at a part they share (a power lead or splitter, the
supply, the controller, or heat after 1-3 h of load: the three box C failures of the day all
came that long into a load), not at disk 15 (INFERRED). With box C out, a lazy umount of hd-15
stayed in D state (it tears XFS down on the dead disk), as did a global `sync`.

## A global sync in a worker waits for every writer

2026-10-16, OBSERVED: row D's worker finished rsync pass 1 of disk 19 at 18:53 and was still in
`sync` (state D) at 21:30, 2 h 36 min later, with 18 GB dirty and 175 MB under writeback, while
three other workers and disk 33 kept writing. sync(2) flushes and waits for every filesystem,
so a worker's sync is held by everyone else's writes. Since then a worker fsyncs only its own
source's copies (one fsync per file through the pool) before verify.
That fsync per file took 5 h 21 min for the 466,599 files of disk 19 on 17 Oct; since then a
worker calls syncfs once on each pool branch, which waits for those disks only, not for the
backup disk or disk 33 (the global sync of 16 Oct was most likely held by the backup disk,
then 27.5 GB behind at 1.5 MB/s; INFERRED).


## rsync --no-inc-recursive copies nothing until the whole tree is listed

2026-10-16. HD_33 (18 TB HFS+ on USB 2, the Linux hfsplus driver, millions of small git
clones) ran for hours with `--no-inc-recursive -AX` and had not copied one file: the log
was still listing `context7/co...`, early in an alphabetic walk of one directory. The flag
gives an exact progress total at the price of listing everything first, which is cheap on a
SATA bay and days on a slow disk with many small files. Without it rsync copies as it
lists. OBSERVED nothing copied after hours; the cause is INFERRED until a restart without
the flag shows a progress line.

## Box C at 04:27 on 16 Oct, and every lost write since 14 Oct
2026-10-17, from the journal (panel runs 2407 and 2550). VERIFIED.

The boot of 15 Oct 22:46 (journal boot -6 on 17 Oct) holds no DART, AER, PCIe or tunnel error
for domain 000a (box C) at all: AER was enabled on its root port and stayed silent. The failure
shows only at the SATA level (queued commands timing out, IDENTIFY failing), then XFS on
disk 15 (sdaa1): writeback errors on two inodes, one at offsets 114.85 to 115.01 GB, the log
write failing, the filesystem shut down at 04:28:56. Box C's SATA controller is a Realtek
`10ec:9100` behind the ASM2464's switch (`1b21:2463`). After the PCI rescan at 13:03 its link
came up at 2.5 GT/s x1, limiting it to 2 Gb/s for eight disks; it is capable of 8 GT/s x2. The
boot-time speed of that link is not in the log lines read.

Failed writes, per boot, device and minute, since 14 Oct (writeback errors, XFS log errors and
shutdowns, failed WRITE commands):

| when | device | what it was |
|---|---|---|
| 15 Oct 02:32-02:40 | sdk | box C's pool disk; window rechecked by bytes on 16 Oct, 0 differ |
| 15 Oct 18:41 | sda10 | the USB exFAT disk, not the pool |
| 16 Oct 03:25, 03:51 | sdb11 | the owner's USB backup disk, not the pool |
| 16 Oct 04:28-04:29 | sdaa, sdaa1 | 15; XFS shut down; never rechecked |
| 16 Oct 12:08 | sdaa | 15, one command; its XFS was shut down since 04:28, no file data |
| 16 Oct 14:16 | sdaa, sdaa1 | 15 (in the pool since 14:03); never rechecked |
| 16 Oct 22:03 | sdp, sdp1 | 15; set aside on 17 Oct (`aside 15` since 21:33, 4373 files) |

15 came back into the pool at 18:15 on 16 Oct and again on 17 Oct, and a copy skips a path
the pool already has, so its files from 04:28 and 14:16 count as copied until they are set
aside too (INFERRED: which paths, if any, lost bytes is not known; a size check cannot tell).

## Where the disks sit since 17 Oct
2026-10-17 13:53 boot, VERIFIED (panel run 2571, each disk found by serial, its PCI domain now).
The owner moved disks between boxes, so a row in migrate-row.sh (a set of disk names) is no
longer one box. The domain of a box is the Mac port its cable is in, not the box itself.

| domain | disks |
|---|---|
| 0008 | 00 08 09 10 11 12 16 24: the four parity disks and four of row C; box C, the one that failed, per the owner; no pool branch |
| 0009 | 13 17 18 19 20 21 22 23 (pool branch 23) |
| 000a | 01 02 03 04 05 06 07 15 (pool branches 04 07 15) |
| 000b | 14 25 26 27 28 29 30 31 (pool branch 31) |

So row A reads box 000b, row B 000a, row D 0009, and row C box 0008 for 09 to 12, then 13 (0009)
and 14 (000b); every parity disk sits in 0008 and is read last in its row. The plan's domain and
port columns still give the old places; names follow the disks by serial.

## The M424 24-bay box and this Mac
2026-10-17, considered as the replacement of the home-made boxes. From the seller's pages and
buyers' answers the owner sent (OBSERVED there, not here): Windows lists the Thunderbolt
version as a "Thunderbolt 3 device router" (an Intel bridge, not an ASM2464); a buyer who opened
it found an LSI SAS3008 card in pass-through mode; a 12G SAS expander backplane from a server,
22 Gb/s through Thunderbolt 3, a 550 W CRPS supply (800 W option) with spin-up in groups of six
a second apart, three 120 mm fans; "Apple systems cannot be used" (macOS on Apple Silicon has no
SAS3008 driver, INFERRED). A SAS version without Thunderbolt looks the same.

On this Mac, VERIFIED: the running kernel has `mpt3sas` (`CONFIG_SCSI_MPT3SAS=m`, 16K pages),
and the `tbt/7.1` source has the whole Thunderbolt 3 path (tipd's TBT alternate mode, the PHY's
TBT mode, the TBT2/3 cable information in `thunderbolt/apple.c`), never run here: every box so far
was USB4. The current cables (1 m) are passive and rated for 80 Gb/s (EUDO `0x2687e000`: speed 4, type
passive). In Thunderbolt 3 mode the 20 Gb/s bit depends on the TBT cable speed the port controller
reports being exactly 3 ("10 and 20 Gbps"), the kind of check patch 0001 had to fix for USB4.
Asahi's own USB4 series (30 Aug 2026) has no PCIe tunnels yet, so nobody else runs this path.

## The backup disk and the hangs in state D
2026-10-17, panel request 413 (disk-check.sh), VERIFIED: WD Game Drive, `WDC WD50NMZW-59A8NS1`,
5 TB, 5400 rpm, 4K physical sectors, on USB at 5 Gb/s through `usb-storage` (not UAS: one command
at a time). SMART passed: no reallocated, pending or uncorrectable sector, no CRC error, no error
logged; 20,967 power-on hours, 51,300 load cycles, 44 °C. Reads of 8 MiB at the start, middle and
end: 71-74 MB/s. No kernel line about it since boot. Besides BACKUP (exFAT, 926 GB) and
BACKUP (ext4) (3.5 TB) it holds eight 23 GB HFS+ volumes named macOS_*.

So the three hangs (rsync of the home folder stuck in D at blk_mq_get_tag and vfs_utimes, a global
sync waiting 3 h, shutdown blocked; 27.5 GB dirty system-wide on 16 Oct) were not damage but
writeback: a slow disk behind a queue of one, and Linux's page cache letting gigabytes of
unwritten data pile up for it, so every writer, sync and shutdown waited with it. A 5 TB 2.5" WD
drive is shingled (SMR, INFERRED from the model), which makes long random writes slower still.
Two backups ran into the same folder at once. Fix: `settings.sh usb-cap on` (at most 256 MiB
unwritten per USB disk, strict) and `backup-home.sh` (one run at a time, lowest priority).

With the cap on (panel request 416, 17 Oct, VERIFIED): the backup ran, 340 MB in 417 files after
14 min with 94,392 files listed; over 20 s the disk was 97 % busy for 29.6 MB written in 60
requests (1.5 MB/s), rsync's writer in D at `wait_on_buffer` (ext4 metadata), nothing else
waiting on it (4.6 GB dirty system-wide were the migration's). Small files on this disk go at its
own pace, which is slow; the machine no longer waits for it.

## HFS+ compression: files Linux reads as empty
2026-10-17, from the hfsplus driver in the 7.1 tree (`fs/hfsplus`), VERIFIED by reading the
source, not run on the Mac: the driver has no decompression code at all, a file's size is its data
fork's, and attributes outside the user/trusted/security/system namespaces are listed with the
prefix `osx.` and read back by that name (`hfsplus_osx_getxattr`). macOS keeps a compressed file's
data in the attribute `com.apple.decmpfs` (header `fpmc`, type, uncompressed size) or in the
resource fork and leaves the data fork empty (INFERRED from how macOS stores them), so under Linux
such a file is empty, its copy too, and size-and-time verification passes. Since 17 Oct
`migrate-row.sh` lists them per source in `state/NN.compressed` (empty files carrying
`osx.com.apple.decmpfs`, with their real size) and holds the source (`NN.held`): nothing formats it
until `rescued NN`. Whether any of the 32 disks holds such files is UNKNOWN until each is scanned
(at its verify, or before its format for one verified earlier, as 26).

## Silent corruption and the sample check
2026-10-17. The quick verify compares every file's name, size and time, never its bytes; the
flush and the kernel-log check catch writes that fail with an error. What none of them catches
is data changed on its way with no error at all: a disk returning wrong data, or memory written
to the wrong place by DMA. The second is the risk specific to this machine: the Thunderbolt PCIe
tunnel, its address offset and its IOMMU path are out-of-tree work never run anywhere else (see
"The tunneled port offsets DMA addresses"). So before a source is formatted, `migrate-row.sh`
reads back 2000 of its files (half picked by count, half by size; 1 MiB at the start, the end and
three random places), each side's cached pages dropped first and the copy read on its branch, and
compares them with the source. Odds of catching a fault that damages a fraction f of files on one
disk: 1-(1-f)^2000, so 86 % at 1 in 1000 and 99.995 % at 1 in 200, per disk (computed, not
measured); a fault rarer than that, or one that damages part of a file outside the pieces read,
passes. `VERIFY=full` compares every byte at about twice the read time. A copy that differs holds
its source (`NN.mismatch`) and stops every worker. Checked on loop disks (tests/eager.sh: 8 bytes
changed in a copy, same size and time, found).

The home backup moved to restic on 17 Oct (the owner's choice, as on the servers), after the
rsync mirror ran at 1.5 MB/s: restic writes large pack files one after another, which a shingled
disk takes at its sequential speed, and later runs write only what changed. Checked with restic
0.18.0 on a loop disk: first run, an incremental one, exclusions (caches, trash, ~/migrate, the
password file, CACHEDIR.TAG folders), the run lock, a missing disk, thinning down to the newest
backup at a 2 % limit. Not run on the Mac yet.

## System audit, 17 Oct
2026-10-17, `system-audit.sh` (panel request 423) and read-only follow-ups (request 424), VERIFIED
unless marked.
- Sound: no failed unit (system or user); SELinux enforcing; firewall on; the NVMe passes SMART
  (1 % used, 124 TB written, no media error, 193 unsafe shutdowns of 1,168 power cycles); btrfs
  has no device error; 189 GiB RAM, zram 8 GiB, systemd-oomd on; NTP synced; `macsmc-rtc` sets
  the clock 8 s into each boot (until then the journal stamps the systemd epoch, 2026-09-14,
  which is why every boot in `journalctl --list-boots` seems to start on that day); the
  tunneled PCIe ports are all active (runtime PM auto, AHCI on), despite the boot-time warnings
  "parent is not active" and "device links to tunneled native ports are missing"; kernel taint
  4 (S, CPUs that differ, the usual on Apple silicon, INFERRED).
- Fixed in settings.sh the same day: updatedb.conf pruned neither `fuse.mergerfs`, `hfsplus` nor
  ~/migrate (`indexer`); smartd scanned before the boxes were up and watched 0 of 32 disks
  (`smartd-rescan`); `UPDATEDEFAULT=yes` and no dnf exclude, so a kernel-16k update would boot
  without the boxes (`kernel-pin`); 20 % of free memory may wait unwritten, 9.6 GB was
  (`dirty-limit`).
- Slow: the flush of disk 19, an fsync per file through the pool, took 5 h 21 min for 466,599
  files (about 20 a second, 280,953 done after 3 h 58 min); replaced by one syncfs per branch.
- Harmless as far as seen: one DART translation fault in the first second of boot on
  597000000.iommu (not a Thunderbolt PCIe DART); disk 02 "timing out command, waited 7s" at
  17:23:19 during the restart of the rows, no I/O error after it (a spin-up, INFERRED); the
  EFI partition's dirty bit (fsck.fat -n: the backup boot sector differs only in that flag).
- Reachable from the LAN: LLMNR (5355) and KDE Connect (1716) only; the panel listens on
  loopback; zone FedoraWorkstation opens 1025-65535 nonetheless.
- Missing or unused: FEX and muvm (x86 programs; binfmt-dispatcher is there), Flathub, a btrfs
  scrub schedule, avd firmware (hardware video decoding); VM guest services (vmtoolsd,
  vgauthd, qemu-guest-agent), mdmonitor and raid-check without RAID, ModemManager without modem.
- Crashes in a week: plasmashell twice (QConcatenateTablesProxyModel), Akregator's https
  kioworker six times on 16 Oct, LibreOffice once.
- Desktop: Plasma 6.7.5 on Wayland, Honeykrisp Vulkan 1.4 and OpenGL 4.6 (Mesa 26.2.4), HDMI
  3840x2160 at 120 Hz, scale 2, no VRR or HDR; an HDR calibration ICC profile from ~/Downloads
  sits on that SDR output; speakers through the j475 convolver, speakersafetyd active.
- Command line still carries `libata.force=3.0G` and `rootflags=subvol=root` twice; 27 updates
  wait (NSS among them).

## Desktop gaps on Plasma 6.7: what exists and what must be built
2026-10-17, from the sources (kernel hid-magicmouse.c and hid-apple.c, KWin, plasma-workspace,
kglobalacceld, xkeyboard-config, Baloo and Qt at their current branches; a research pass, links
below), not tried on this machine yet:
- Magic Mouse: hid_magicmouse sends the surface's touches as ABS_MT_* events, which libinput
  drops on purpose (quirk AttrEventCode=-EV_ABS) but /dev/input/eventN still carries: a daemon
  can see a two-finger double tap and call KWin's `view_zoom_in` over D-Bus. Its parameters
  (emulate_3button, emulate_scroll_wheel, scroll_speed 0-63, scroll_acceleration,
  report_undeciphered) are 0644, writable at runtime. Nothing upstream stops a resting finger
  from scrolling while the mouse moves (the scroll code reads finger travel only).
- KWin Zoom: Meta+= / Meta+- / Meta+0 (view_zoom_in, view_zoom_out, view_actual_size),
  Meta+Ctrl+scroll, and a three-finger pinch on the touchpad; MouseTracking and MoveZoom*
  shortcuts for moving around. Tap gestures on Wayland only through the InputActions KWin plugin
  (taj-ny), built from source.
- Fullscreen windows sit above panels by design; maximized plus `[Windows]
  BorderlessMaximizedWindows=true` and a panel set to dodge windows is the way to have both.
- Apple's SF font licence allows mock-ups for Apple platforms only; Inter (OFL,
  rsms-inter-fonts in Fedora) is the usual stand-in.
- Stage Manager: nothing equivalent; the built-in "Minimize all other windows" (Meta+Shift+O,
  Plasma 6.6+) and the kwin-solo-window script come closest.
- Animations: kdeglobals `[KDE] AnimationDurationFactor` (0 none, lower faster).
- Keyboard: `gb` variant `mac`, model `applealu_iso`; ñ through a compose key
  (`compose:rwin`: right Cmd, ~, n); the macOS Option+n way needs an own xkb symbols file.
  hid_apple has iso_layout, swap_opt_cmd, fnmode (all 0644).
- Program shortcuts: the defaults come from X-KDE-Shortcuts in .desktop files and are switched
  off with `_launch=none` under `[services][<file>.desktop]` in kglobalshortcutsrc.
- The wheel changing a hovered slider, spin box or combo box has no setting anywhere (KDE bug
  399324); Firefox already leaves number fields alone.
- Baloo indexes $HOME only and skips removable disks; plocate is a separate indexer
  (/etc/updatedb.conf).
- Found here besides: the Magic Mouse setting of ux-fix.sh did not hold after a reboot
  (settings.sh status, 17 Oct: middle click emulated, scroll_speed 32, while modprobe.d said
  0 and 1); the driver loads from the initramfs, which lacks that file (INFERRED), so a
  tmpfiles.d entry now sets the values once the system is up.
Sources: https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c ·
https://gitlab.freedesktop.org/libinput/libinput/-/blob/main/quirks/50-system-apple.quirks ·
https://invent.kde.org/plasma/kwin/-/blob/Plasma/6.7/src/plugins/zoom/zoom.cpp ·
https://wiki.inputactions.org/main/devices/touchpad/triggers/tap.html ·
https://developer.apple.com/fonts/ · https://github.com/aario/kwin-solo-window ·
https://gitlab.freedesktop.org/xkeyboard-config/xkeyboard-config/-/blob/master/symbols/gb ·
https://bugs.kde.org/show_bug.cgi?id=399324 ·
https://invent.kde.org/frameworks/baloo/-/blob/master/src/lib/baloosettings.kcfg

## kwin-solo-window is not absorbed
2026-10-17, read at aario/kwin-solo-window 30394b1 (2025-09-19, the last commit) and its open
pull requests 3, 5 and 6: one 512-line main.js, GPL-3.0, its metadata names "Gemini" as the
author. The overlap test reads `.left`/`.right`/`.top`/`.bottom` of a window's geometry, which
pull request 5 (2026-05-21, unmerged) replaces with x/width because they no longer exist on
Plasma 6.6 and later (the request's own reason; not tried here). Every sweep is deferred through
a D-Bus call to KWin's `supportInformation`, which makes KWin build its whole debug report on
each window event. KWin's own Minimize All script (src/plugins/minimizeall, off by default,
`[Plugins] minimizeallEnabled` in kwinrc, loaded on reconfigure) has "Minimize all other
windows" on Meta+Shift+O and a variant for the active screen: `ux-fix.sh solo on`. An automatic
mode stays a script of our own (BACKLOG, Stage Manager-like mode).

## The TV's colour profile from oled-tv-calibrator
2026-10-17, read at bses2018/oled-tv-calibrator master and generated here with its
`generate_profiles(2000, dir, tv_model="LG G5")`: "LG G5 HDR Calibration 2000 nits.icc" is its
"Native HDR" profile, 808 bytes, the same for every TV (the model only names it, the nits only
set `lumi` and the MHC2 maximum). It holds no measurement: rXYZ/gXYZ/bXYZ fixed at x,y
0.670,0.312 / 0.273,0.659 / 0.153,0.045 (between sRGB's and P3's), wtpt D65, an identity
`chad`, a gamma 2.2 TRC, an identity MHC2 (2-entry curves, identity matrix). KWin
(src/core/iccprofile.cpp, master of 17 Oct) takes the white from `chad`, so D50, the primaries as
stored, the MHC2 curves as its gamma table (identity here) and `lumi` as the peak. The visible
effect (INFERRED): KWin maps sRGB into that wider gamut, so colours come out less saturated than
with no profile, where sRGB values go to the TV as they are. An earlier research note said the
profile crushes shadows: wrong, its curves are the identity. KWin can take the primaries from the
display's EDID instead (KScreen's Built-in source; ColorProfileSource EDID). The other five
profiles it writes (Virtual SDR, Auto HDR) carry PQ-domain gamma tables meant for Windows' HDR
mode; on an SDR output they would bend the tone curve (INFERRED from the code). Generated tail (bytes 129 on) sha256
2c0ee6293f21c046345eb2e4dad0b4aa49a97933a560a9b9db75dbc384f8bf20; the header holds the date.
`icc.sh make` (18 Oct) writes the same profile, every tag identical but `desc` ("Wide gamut, gamma
2.2, 2000 nits") and `cprt`; Little CMS (Pillow's ImageCms) opens it.

## smartd beside KDE's disk health monitor
2026-10-18, read at KDE/plasma-disks master (src/smartmonitor.cpp, src/helper.cpp): KDE's
monitor is a kded module that runs `smartctl --all --json=c` on each disk through a KAuth
helper when it starts and every 24 h, and notifies when a disk's overall status fails or a few
attributes look unstable; it runs only inside a desktop session and has no `-n standby`, so it
spins sleeping disks up. smartd here checks all 33 disks every 30 min without waking a sleeping
one (`-n standby,48`, settings.sh smartd-quiet), logs every attribute change and error to the
journal that link_report and disk-check.sh read, runs with nobody logged in, and can schedule
self-tests. The two overlap only in the failure notice.

## Closing a window from the task switcher
2026-10-18, the owner: with the switcher open (Cmd+Tab), closing a window with its X leaves
some other windows out of the switcher until the next Cmd+Tab; Tab then shows a missing one while
the shown ones go. VERIFIED the same day (KWin 6.7.5, Qt 6.11.2, libplasma 6.7):
- Not KWin's list: after each close ClientModel holds every remaining window (lab_probe log,
  cells 82352 and 82589: count 7, 6, 5, each tile rebuilt with its caption).
- "Breeze" and "Thumbnail Grid" are one layout: 6.7's look-and-feel packages ship no window
  switcher, so LayoutName org.kde.breeze.desktop falls back to thumbnail_grid
  (TabBoxHandlerPrivate::createSwitcherItem; cell 82282).
- The cause: Thumbnail Grid sizes its frame for N columns (dialogMainItem width = N x cellWidth)
  and its GridView fills that frame. PlasmaQuick::Dialog sizes the window as the item plus its
  frame margins truncated to whole pixels (DialogPrivate::syncToMainItemSize builds a QSize from
  the qreal margins) and, once the window is exposed, gives the item back the window minus the
  margins unrounded (Dialog::resizeEvent). With fractional margins (here between 16 and 17 px a
  pair) the item ends one pixel short: 888 became 887, so the GridView fits N-1 columns, the
  spilled row is clipped by the frame, and scrolling to it hides the rest. At the first show the
  window is not exposed yet, so the first layout is right; every close after that hits it.
- Replayed in plain Qt Quick 6.11.2 with a 1 px trim: the same missing tiles; with the GridView
  sized by its own columns and rows (ux-fix.sh switcher), every tile.
Upstream: the root is libplasma's Dialog (one rounding for both directions, or margins kept as
qreal); Thumbnail Grid can also stop depending on the frame's exact width.
The owner, after ux-fix.sh switcher on: "FIXED!" (18 Oct). The form offered to KWin (two
named properties for the grid's size) is the same change, checked equal by applying both to 6.7.5.

## HackedSystem on Linux, as read on 18 Oct
Read at its master 2c72300 (its key points checked in the code): a Django
panel whose collectors (graph/collectors/*.py, `@collector(on="linux"|"macos"|"any")`) record
nodes; desired state (graph/state.py) exists for three kinds only (defaults_key, launchd_job,
systemd_unit), with a hash-chained ledger and undo. Linux has one adaptor, graph/collectors/linux.py:
systemd units and timers, rpm/dpkg/flatpak packages, sockets and connections, network, accounts,
/etc digests, lsblk, hardware, boot. Not there for Linux: SMART, files no package owns (rpm -qf),
a Fedora clean-install baseline, restic backups, a wanted-programs list, kernel modules, sysctl,
KDE settings. Two faults, VERIFIED by reading: the checks collector keeps the default on="macos"
(graph/collectors/system.py:149), so the Linux checks timer's `collect checks` is refused
(engine.py: a collector for another system); the watcher reports or enforces only defaults_key
and launchd_job (graph/watch.py targets), never a systemd_unit.
Its own rules: nothing may wake an external disk; the panel runs without sudo.

## Metal, Vulkan through MoltenVK and Honeykrisp on this Mac
27-28 Oct, macOS 15, llama.cpp 2280f0f (macos/collect.sh: llama x3, ablate, ops, vulkan; MoltenVK 1.4.2 from Homebrew).
VERIFIED unless marked. Linux figures from the entries above.
- llama.cpp's Vulkan backend through MoltenVK on macOS is as slow as Honeykrisp on Linux; Metal is 2-3x both:

  | model | Metal pp512 / pp2048 / tg128 | Vulkan on MoltenVK | Honeykrisp (Linux) |
  |---|---|---|---|
  | Llama 2 7B Q4_0 | 1518 / 1538 / 121.5 | 788 / 836 / 59.9 | 760 / - / 64.9 |
  | GPT-OSS 20B | 1945 / 2148 / 125.0 | 992 / 1221 / 82.7 | - |
  | Qwen3-Coder-Next Q8 | 1535 / 1817 / 67 | 422 / 574 / 24.8 | 486 / 780 / 32.1 |

  So the gap is llama.cpp's Vulkan shaders and graph on this GPU, not Mesa or the Linux kernel (INFERRED: MoltenVK
  adds its own SPIR-V to MSL translation, and reports int dot 0 and no matrix cores, as Honeykrisp without coopmat).
- One generation-step matrix-vector, q4_0 4096x14336 (test-backend-ops perf): Metal 37.2 us (~890 GB/s of weights),
  the Vulkan shader through MoltenVK 100.0 us (~330 GB/s). Linux's q8_0 shape of the same size: 123 us.
- Launch cost, metal-chain against vk-chain: a dependent Metal launch 2.27 us (free 0.30), Honeykrisp 4.0-4.2 us. One
  dependent fma 1.39 ns on Metal, 1.57 ns on Linux: the same clock.
- Metal's graph work in generation (ablate, tg128): fusion, concurrent dispatch and reordering all off cost Llama 2 7%,
  GPT-OSS 20B 13%, GPT-OSS 120B 15%, Qwen 28% (fusion alone 22%), Gemma 29% (fusion alone 25%). Per token Metal fuses
  RMS_NORM+MUL (all), the MoE reduce (GPT-OSS), and on Gemma also RMS_NORM+MUL+ADD, MUL+7xADD and the whole router
  (SOFT_MAX+ARGSORT+GET_ROWS+SUM_ROWS+CLAMP+DIV). Prompts move 3-8%.
- Speculation leaves greedy text identical on Metal for Llama 2, GPT-OSS and Qwen; Gemma's text differs per setting
  (INFERRED: batched verification rounds differently). Qwen with ngram-mod 128: 216 t/s on Metal, 55-59 on Linux.
- Power: GPU at 1398 MHz throughout; ~113 W on Llama 2 prompts, Qwen ~94 W prompts and ~44 W generation.

## The ANE overlay panicked the boot: DART power island
29 Oct, trial kernel 7.1.13-tbtwip with omarchy-ane's t6022-ane overlay (ae189112). VERIFIED unless marked.
- Panic 2.66 s into boot: "Asynchronous SError Interrupt" in apple_dart_probe, udev loading apple_dart (panic QR log).
- The overlay puts ANE dart0 (0x285800000) in pmp, dart1/2 in ANE_CPU. macOS 15 here: dart-ane0 holds all three
  windows, power-gates 0x1fb = ANE-SYS-DART, a virtual gate under 0x3c ANE_SYS (pmgr 0x260). INFERRED: dart0 was read
  with ANE_SYS off. kernel/dt/t6022-ane-dart-power.dts moves all three to ANE_SYS; it booted (below).
- The overlay reaches AIC and the power controllers by labelling existing nodes. dtc 1.7.0's fdtoverlay gives such a
  node a new phandle and leaves its other users dangling (synthetic tree here); dtc 1.7.1+ resolves the conflict.
  tbt-kernel.sh now refuses a tree with more unresolved phandle references than before its overlays.
- The stock kernel hangs on trial device trees and they live in boot.bin, so a broken tree blocks both kernels:
  the way back is boot.bin.stock (now also boot.bin.previous) from macOS. TBT_OVERLAYS is empty by default.
- With the fix (TBT_OVERLAYS=t6022-ane, installed with tbt-kernel.sh dtb), 29 Oct 01:36: the boot came up clean, the
  three ANE DARTs initialized, the node bound when loaded. ane_t6021 ae18911 by hand: firmware booted (handshake,
  channel table validated), /dev/accel/accel0; omarchy-ane-smoke add-fixture 20/20 bit-exact against the golden
  sha256, min 0.398 ms, median 0.418 ms: the first run of the M2 Ultra's die-0 Neural Engine under Linux here.
  The module pins itself until reboot. omarchy-ane-check's only FAIL is "not built for the kernel" (no dkms
  install: loaded by hand on purpose). Report: var/ane/report-20261029-014332.

## Where a generated token goes on Honeykrisp
25 Oct, M2 Ultra, coopmat Mesa 795ae42a71 with HK_PERFTEST=designedusccdmbarrier, llama.cpp f2cc728 and 2280f0f
(cells 4058-4154, vk-chain in this repository). VERIFIED unless marked.
- Qwen3-Coder-Next Q8 (80B, 3B active): 28.4-32 t/s generation, 1878 GPU launches per token, all on the GPU, the CPU
  idle (perf). Llama 2 7B Q4_0: pp512 529, tg128 64 here; Metal 1238 / 94 (llama.cpp discussion 4167), another
  Asahi M2 Ultra 206 / 36 (discussion 10879).
- The GPU runs at full clock: one dependent multiply-add 1.57 ns = 2.2 cycles at 1398 MHz, Apple's figure; the
  device tree's table is complete (9 states to 1398 MHz with power). A loop step costs ~36 cycles (while, jmp_any).
- A launch that waits on the one before costs 4.0-4.2 us (0.3 us when independent, coopmat only); pipeline switches
  and rebinds add nothing; ggml's op form (3 buffers, 30 push constants, index divisions, 187-instruction preamble)
  adds ~1.6 us. So ~10 ms of a ~33 ms token is fixed per-launch cost (INFERRED from 1878 x 4.2 + 1100 x 1.6).
- Barriers in a shader ~0.1 us, a GPU load 0.22 us (cache) to 0.5 us (memory): normal. Shader size does not matter
  (soft_max and rms_norm made 10-20x smaller kept their time).
- The rest is the matrix-vector work at low efficiency: dense q8_0 512x2048 25 us (44 GB/s), expert 10 of 512 at
  512x2048 39 us (~280 GB/s), large 4096x14336 123 us (~510 GB/s, rows=4, large workgroup). Small matrices are
  latency bound: few workgroups, each walking k alone (INFERRED). Rows per workgroup: q8_0 best at 4, q4_0 at 1;
  Qwen as a whole at 2.
- Small matrix-vectors are latency, not bandwidth (cells 4156-4172): every type costs 21-34 us at 512x2048
  (f32 4 MB to q4_0 0.6 MB, 527 to 3900 instructions, any workgroup form); a minimal f32 matrix-vector costs
  1.6 us per launch when launches overlap and 19 us when each waits on the one before; batching its loads by 8
  changes nothing; a plain add pays the same wait (16 KB: 0.7 free, 4.3 chained; 4 MB: 12.8 and 22.4). So a
  dependent launch costs ~4 us plus a share that grows with its size: the GPU draining and filling again between
  ops (INFERRED). The levers are fewer dependent launches (fusion) and that drain; split-k does not apply (ggml
  already spreads k over a workgroup's threads). Metal's figures for the same tests are UNKNOWN.
- The barrier word between launches (coopmat Mesa's HK_CDM_BARRIER_MASK, cells 4185-4194): bit 8 (or bit 9, the
  same cost and also correct) is the wait for the previous launch; without it (0x7f) Llama 2 7B Q4_0 generates
  94.6 t/s, Metal's 94, prompts 621 (Metal 1238), but launches overlap and results are wrong (TOP_K fails, other
  text; test-backend-ops then crashes in test_top_k::err on the garbage indices). Bits 4-6 are needed too (0x107,
  0x10f fail TOP_K). No other bit of 9-19 orders the launches for less. 0x17f (designedusccdmbarrier) passes all
  21303 tests and is ~1 us cheaper per launch than the default 0xfffff. So the generation gap to Metal is the
  serialization of dependent launches itself: each waits for the previous one's whole latency (a 512x2048
  matrix-vector 19.5 us waited, 5 us overlapped). How Metal keeps order and still overlaps is UNKNOWN.
- A launch's latency against its workgroups (cell 4195, plain add, waited on): 1 MB 68 us over 8 workgroups,
  13 over 76, 8.2-8.5 over 300-1000, 16.6 over 4096; 16 MB 963, 128, 53-58 (~630 GB/s). So a dependent launch
  costs ~4-5 us however it is shaped, and one with fewer than ~300 workgroups of 256 threads waits on the few
  cores it runs on: the single-workgroup rows of ggml (RMS_NORM, SOFT_MAX and top-k over one token's row) are in
  that case.
- CORRECTION (cell 4209, 25 Oct): in one test-backend-ops process the first perf case is slow and every later one
  is not (q4_K 512x2048: 25.1 us first, then 13.2-13.7; q8_0 after it 13.9), so the per-op figures above taken with a
  -p filter for one case (the 21-34 us matrix-vectors, ADD's 8 us floor, RMS_NORM 12, SOFT_MAX 25) carry ~11 us of
  that first-case cost. Warm, ggml's small q8_0 matrix-vector is ~13.5 us against a chained 1 MB add's 8.2 us
  (vk-chain): its excess is ~5 us a call, not 15, ~2.5 ms of a Qwen token (INFERRED from ~470 calls). vk-chain's
  figures repeat each launch 1500 times and stand.
- Barriers per Qwen token (cells 4215-4218, GGML_VK_SYNC_LOGGER, llama.cpp 2280f0f): one every ~3 node lines,
  1-4 launches between two barriers, most often 2. With the graph allocator's memory reuse switched off (an
  env-gated experiment in ~/src/llama.cpp-up's ggml-alloc.c, GGML_ALLOC_NO_REUSE) the count barely moves (3144 to
  3108 in two tokens) and generation does not rise: the barriers are real data dependencies, not reuse.
- Single bits off 0x17f (cell 4222): bit 0, 1, 2 or 3 alone off (0x17e, 0x17d, 0x17b, 0x177) passes 8 test groups and
  keeps the reference text, but Llama 2 7B stays at 64.3-64.6 t/s (0x17f 64.5); bit 4, 5 or 6 off fails (MUL_MAT,
  TOP_K, FLASH_ATTN_EXT), also with bit 9 for bit 8. So in a real model 0x17f is as fast as any correct word.
- agxperf (cell 4225: coopmat + xingjianll's compiler changes, vendor/mesa/agx-llm-perf.patch): prompts +21% on
  Llama 2 7B (639 vs 526) and +32% on Qwen Q8 (490 vs 370); generation -9% on Llama (58.5 vs 64.5), Qwen the same;
  ARGMAX tests fail (9 of 21303: ARGMAX and COUNT_EQUAL). It does offer cooperative matrices (cell 4226; the
  'not offered' line was the check run in the build's PATH). Split (cell 4226, Llama 2 7B pp/tg, cache off): all
  three 639/58.4, ILP off 632/59.0, clustering off 616/65.8, both off 580/64.4, ARGMAX failing in every case, so
  bit 47 breaks it (and gives ~+10% prompts); clustering costs generation. agxilp (agx-ilp.patch) drops bit 47.
- agxilp (cell 4228, all 21303 tests pass): clustering on, Llama 2 7B 547/53.6, Qwen Q8 417/31.6; AGX_CLUSTER_OFF=1,
  Llama 543/64.1, Qwen 384/33.0 (coopmat 526/64.5, 370/32.6). So without bit 47 the gain is small: +3-4% prompts and
  Qwen +1% generation with clustering off; +13% Qwen prompts at -3% generation with it on. Most of agxperf's
  prompt gain was bit 47 together with the others; its ARGMAX fault is the thing worth fixing (report to its author).
- Bit 47 bisected (cell 4233, agxperf, clustering off, Llama 2 7B pp/tg): off 546/65.6 (tests pass), loads and stores
  618/65.4 (ARGMAX 0/7, COUNT_EQUAL 0/2), loads only 617/65.8 (all pass), stores only 547/65.4 (pass). The gain is
  on lload, the fault on lstore (ARGMAX stores to local memory then loads the same words after a barrier).
  agxperf now sets it on loads only by default (AGX_BIT47=2).
- agxperf, bit 47 on loads (cell 4241, 26 Oct): all 21303 operator tests pass with clustering off and on. Clustering off:
  Llama 2 7B 617/65.4, Qwen Q8 432/33.6 (coopmat 526/64.5, 370/32.6: prompts +17%, generation +1-3%). Clustering on:
  Llama 640/58.8, Qwen 491/32.2 (prompts +22-33%, generation -1 to -9%). The default driver for llama.cpp here is
  agxperf with AGX_CLUSTER_OFF=1; clustering on only for prompt-heavy work.
- Model sweep (cell 4252, pp512/tg64, agxperf clustering off, rows 1 | rows 2; coopmat in brackets): Llama 2 7B Q4_0
  616/65.6 | 617/61.5 (528/64.5); GPT-OSS 20B Q8 747/69.2 | 749/67.5 (641/66.2); Gemma 4 26B-A4B Q4_K 636/38.5 |
  636/39.2 (551/37.9); GPT-OSS 120B Q4_K 353/48.4 | 353/48.0 (297/46.8); Qwen3-Coder-Next Q8 433/31.1 | 432/32.9
  (370/30.4); Qwen3.8-Flash-Next Q4_K (111 GB) 215/18.5 | 216/18.9 (185/18.5). agxperf +15-19% prompts on every
  model; rows 2 for the Qwen and Gemma MoE models, rows 1 for GPT-OSS (mxfp4 experts) and dense models.
- Qwen3.8-Flash-Next Q4_K, the server on the code edit (cells 4258, 4265): none 18.5 t/s, ngram-mod 22.0 (same text),
  MTP head 25.9 (+40%), MTP + ngram-mod 22.8; the MTP answers differ from the plain one (as Gemma's did): speculation
  with MTP is not bit-exact here. Loading a model file from the mergerfs pool fails in llama.cpp ('read error: Bad
  address'); from the warm copy it loads: models load from ~/Projects/_llm, not from the pool.
- Settings that won: --spec-type ngram-mod +51% on code edits; designedusccdmbarrier +7-9% (21303 operator tests
  pass); -ub 8192 prompts 593 to 676. Lost or unsafe: usccdmbarrier and nobarrier stall the GPU (UI lag, 0.2 t/s);
  ngram-cache; integer dot; the 25 Oct upstream llama.cpp (prompts 523 vs 593).

- Matmul tiles, 26 Oct (cell 4280, vendor/llama/vk-tiles.patch on llama.cpp-up, agxperf, clustering off): upstream
  builds only the medium tile on Honeykrisp (128 threads, 64x64). The same tile at 256 threads and 128x64
  (GGML_VK_WT_M=256,128,64,,32,32) gives prompts +23%/+19% on Llama-2 Q4_0 (620/678 to 762/804, pp512/pp2048) and
  +16%/+17% on Gemma Q4_K (611/770 to 709/902); every MUL_MAT and MUL_MAT_ID test passes. The large tile as upstream
  shapes it (128 threads, 128x128) loses 37-53%; at 256 threads it is near the winner on Llama-2 and worse on Gemma
  at pp512. BK 32 and WMITER 1 change nothing. The first run (4276) measured the old binaries: its build had failed.
- Tiles, sweep 2 (cell 4285): 256 threads 128x64 stays the best all round, Qwen Coder Q8 pp512/pp2048 399/596 to
  449/680 (+12%/+14%). 64x128 at 256 threads is 1% faster on Llama-2 and 9% slower on Gemma pp512; 512 threads 128x128
  equals it at pp2048 and loses at pp512; 128x128 at 256 threads and the 256-thread large tile beside it lose on
  Gemma; WMITER 1 is the same. BK 16 is wrong: 430/555 MUL_MAT pass (quantized types, error 1.0). llama-run.sh sets
  the winner (GGML_VK_WT_M=256,128,64,,32,32); llama.cpp-tune-prod needs vk-tiles.patch for it to take effect.
- In llama.cpp-tune-prod (cell 4287, commit 5bd6cef there), Qwen Coder Q8 with the 256-thread tile: pp512 434 to 488,
  pp2048 672 to 780 (+12%/+16%), tg64 the same (33.2). Batches of 4 and 8 tokens run at 79-105 t/s, a batch of 16 at
  39-43 t/s: past 8 columns ggml leaves the matrix-vector shader for the matmul one, so a speculation step that
  verifies more than 8 tokens costs more than one that verifies 8 (INFERRED from the shapes, not traced).
- Bit 47's origin, checked 26 Oct: xingjianll's commit 09a3107 ("agx: set bit 47 on lload/lstore", branch
  agx-llm-perf as fetched 25 Oct) sets it in the encoding lload and lstore share, so stores got it too; he says
  (GitHub, 26 Oct) he meant loads only, stores having no effect on speed. Clustering against clustering off (cell
  4241): prompts +4% Llama 2, +14% Qwen; generation -10% Llama 2, -4% Qwen (the +33%/-9% once in llama-run.sh was
  against coopmat).
- ngram-mod draft length (cell 4358, Qwen Coder Q8, prod with the 256-thread tile, a 1237-token code edit, greedy):
  none 30.3 t/s; default 64/48 46.1 (+52%, 989 of 1280 drafted accepted); 32/16 41.2; 16/8 32.3; 8/4 22.4, slower
  than none. Every setting gives the same text. So the 9-16 token batch cost does not argue for short drafts: long
  drafts on a code edit are accepted at 77%+ and one long batch beats many short ones.
- Longer ngram-mod drafts (cell 4361, same edit): 64/48 49.1 t/s (46.1 in 4358: ~6% run to run), 128/96 55.3, 128/32
  55.2, 256/192 54.7; the same text. llama-run.sh's qwen profile drafts up to 128. Batch-size curve, Qwen Coder Q8 prod,
  t/s at 1 2 4 8 9 12 16 24 32 64 128 512 tokens: 34 54 81 105 27 34 43 62 78 134 216 486. Past 8 tokens the speed
  falls 4x (9 tokens take 333 ms against 76 ms for 8) and only 64 tokens get back above it; the small tile makes 9-32
  worse (22-58 for MoE layers, 17-49 for all). So the matrix-vector path's limit of 8 columns is the cliff: a draft
  that verifies 9-48 tokens pays more than one of 64.
- MUL_MAT_ID's matrix-vector limit (cell 4362, vk-mmv-id.patch, Qwen Coder Q8 prod, t/s at 8 9 16 32 48 64 128 512
  tokens): limit 8 98 26 42 75 103 125 209 463; limit 64 105 37 59 97 123 142 219 484; limit 128 drops 128 tokens to
  186. MUL_MAT_ID 1109/1109 pass with every case on that path. The code edit at 128-token drafts: 57.3 (8), 57.5 (32),
  58.9 t/s (64), the same text; small, as those verification batches are ~100 tokens. llama-run.sh sets 64. What is
  left at 9 tokens (37 against 105 at 8) is the dense MUL_MATs: mul_mat_vec_max_cols is a compile-time 8 with one
  pipeline per column count (ggml-vulkan-types.h).
- Dense matrix-vector path up to 16 columns (cell 4381, vk-mmv-cols, prod, GGML_VK_MMV_ID_MAX=64, t/s at 8 9 10 12
  16 24 32 tokens): Qwen cut 8 106 37 40 47 59 80 97, cut 16 106 107 108 112 115 80 97; Gemma 137 45 .. 73 to 136
  138 140 143 150; Llama 2 171 42 .. 75 to 172 168 168 158 154. MUL_MAT 2275/2275 pass with every case up to 16
  columns on that path. The cliff now sits at 17 tokens. Gemma MTP drafts 3/6/12 on the code edit: 29.7, 28.2, 28.5
  t/s, so longer MTP drafts do not pay; its text was empty in all three (md5 of ''): the 1500 tokens went to
  reasoning, so that test checked speed only.

## Standing owner decisions (kernel)
Kept here so a resumed session does not re-ask them; each was stated by the owner.
- 2026-10-14: the kernel stays as it is until the copies are done (agreed before the migration): a new kernel or a stock boot mid-migration puts the enclosures and the running copies at risk. Lines that need the stock kernel or a new one wait in the backlog.
- 2026-10-18, the projects: kernel changes are made to the standard of the kernel community (mainline style, professional), kept in their own repository (this one); linux-lab is the Asahi, Fedora, KDE and Mac layer meant for anyone with this hardware after a plain Asahi install, kept as a parallel layer where upstream will not take it; HackedSystem gathers the daily administration, prototypes welcome; the migration stays private and ends.
- 2026-10-18: the kernel tree is ~/Projects/asahi-linux-tbt (the owner); tbt-kernel.sh and magicmouse.sh default to it. The tree the running 7.1.13-tbtwip was built in, ~/src/linux-asahi-tbt, is gone.
- 2026-10-18, licences: "use common sense, best matching for this, inherit from parents when convenient" (the owner, after rejecting a closed-source section another agent had added: "this project is actually open-source"). This repository is GPL-2.0-only, as the kernel files its patches change; linux-lab is GPL-2.0-or-later. ansible's projects.py accepts an open licence named by SPDX id in README License with a LICENSE file.

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
Owner's boot dumps and captures, 2026-10-11, kernel `tbt/pcie` at `1b233c05d585`. Verified: all six controllers probe at boot without a cable (root ports `106b:1014`, domains 0008 to 000d, 64 RID/SID entries, so the T8103 register layout is right; `LINKSTS 0xa9000200`, `TUNSTAT 0x1` while idle); m1n1 1.6.1 fills in the tunables; the six IOMMUs probe after their controllers. With an enclosure on the port of `usb4_0`: `Link up` 13 ms after the PCIe paths, bridges `1b21:2463` on buses 1 and 2, AHCI `10ec:9100` (nine ports) on bus 3, MSI assigned, and the enclosure stays on USB4 instead of dropping after 10 s. Not working in that run: DMA (next entry), so no disks. Once, unplugging and plugging again froze the machine; nothing of that boot's log survived. The owner sees macOS panic on replug of the same enclosure too. `tbt-capture.sh` now flushes the kernel log line by line to a `.klog` file.

## The tunneled port offsets DMA addresses
Same run. The AHCI controller was given IOVAs just under 4 GB and the IOMMU reported `translation fault ... stream:1 code:0x2 (NO PGD FOR IOVA) at 0x100fffc0440`: the port adds 0x100_00000000 to the address a device uses. This matches macOS's `vm-base` of 0x100_80000000 for `dart-apciec`. Fix in `bf1b5bf89f` and `523466d61f0b`: `apple,dma-offset` on the IOMMU node makes the driver map at address plus offset, and `apple,dma-range` keeps device addresses below 4 GB. Whether addresses above 4 GB would also just be offset is not known, hence the limit. The internal PCIe IOMMUs have a `vm-base` with the same prefix in macOS yet work without an offset in Linux; not understood.

## Disks work; what eject and replug do
Owner's capture of 2026-10-11 17:04, kernel `tbt/pcie` at `523466d61f0b`. Verified: with the DMA offset no translation fault is logged, the AHCI controller brings up eight 18 TB disks at 6.0 Gb/s with NCQ, each with a 200 MB EFI partition and one HFS+ volume (not APFS; the APFS entries in `lsblk` are the internal SSD), all read-only through the udev rule. The USB4 link is 2 lanes at 20 Gb/s; the SATA controller's own PCIe link is 8 GT/s x2. The kernel's "2.000 Gb/s available PCIe bandwidth, limited by 2.5 GT/s PCIe x1 link" line describes the virtual link through the tunnel and is not a measured limit (inferred; `tbt-kernel.sh bench` measures).
Replug: after the PCI devices of the enclosure were removed through sysfs, the port controller reported a mode change (`set cable state: 0` then `2` within a millisecond), ACIO restarted, the PCIe link came up again and the AHCI controller re-enumerated by itself, at first with all SATA links down. Inferred: the ASM2464 reconnects when its PCIe side goes unused, like its 10 s USB4 fallback. So `eject` now removes only the disks (SCSI delete after sync) and leaves the controller bound. The physical unplug that followed, with `ahci` bound and no disks attached, went through cleanly: `Tunnel error`, `stopping tunnel`, `failed to stop engine (-19)` per port, controller reset, root port back, and the next plug brought everything up again. The one freeze happened in the run where DMA was broken and every port was in error handling; pulling an enclosure with disks attached and busy is still untested.

## Why the GPU driver is off on the 7.2 tree
Probed 2026-10-11 by building `drivers/gpu/drm/asahi` on `tbt/pcie` with `depends on BROKEN` removed (rustc 1.97, bindgen 0.73.2, clang 18, 16K pages). The kernel crate builds; the driver stops in its first compile pass with 56 errors in nine files. They are API changes of the Rust kernel crate in 7.2, not typos: the GPUVM abstraction was replaced (`DriverGpuVm` now wants `Object`, `VaData`, `VmBoData`, `SmContext`, `sm_step_map/unmap/remap`; `UpdatingGpuVm`, `GpuVaFlags`, `OpUnMap`, `OpReMap`, `DriverGpuVmBo` are gone), which hits `mmu.rs`, the GPU's address-space code; the DRM driver trait changed (`FEATURES` gone, `RegistrationData`, `ParentDevice`, `Data` required); `kernel::iosys_map` and `shmem::SGTable` moved; and one macro change gives `u8: Deref` errors at eight firmware-structure sites. Later compile passes will add more. Upstream state the same day: `asahi-wip-7.2` unchanged since 2026-08-31, `bits/210-gpu` ends in the commit that marks the driver broken, no `asahi-7.2` tag, `asahi-wip` is still 7.1.13. Decision: do not port the GPU driver here; it is a rewrite of memory-management code that cannot be tested from the sandbox, and Asahi is doing it. For a kernel with both GPU and Thunderbolt disks, backport the USB4 stack instead: on top of v7.2 it is about 30 commits (`bits/270-thunderbolt` 21 plus the CIO reset driver, the Thunderbolt-switch part of `bits/260-spmi-typec` 4, `bits/170-atc` 3, device trees) plus this lab's 9, onto tag `asahi-7.1.13-3`, the source of the stock Fedora kernel. This replaces the earlier "No backport to 7.1" decision, which was made before the GPU mattered.

## The 7.1 backport
Built 2026-10-11 as branch `tbt/7.1` of the fork, on Asahi tag `asahi-7.1.13-3` (same commit as branch `asahi-wip`, the source of the stock Fedora kernel). What it took: cherry-picking Sven Peter's Thunderbolt commits fails at the first one, because 7.2 reworked the Thunderbolt core for non-PCI host interfaces, so `drivers/thunderbolt`, `include/linux/thunderbolt.h` and `drivers/net/thunderbolt` are taken whole from `tbt/pcie` (one include adapted: 7.2 split `mod_devicetable.h`). `tipd` (92 added, 31 removed lines apart) and `phy/apple/atc.c` (120/82) are taken whole too; the CIO reset driver, the Type-C Thunderbolt switch and the lab's PCIe and IOMMU commits are cherry-picked, the IOMMU one with a small conflict (7.1 derives the address mask from the table levels). Device trees are the trap: 7.2 moved every DART's DMA window from `apple,dma-range` into five-cell `iommus`, which is exactly what crashes the 7.1 display driver, so only the USB4 and PCIe hunks are taken and the NHI DARTs are written in 7.1 form (one cell plus `apple,dma-range`). Because the display nodes are untouched, the stock kernel should now tolerate these device trees; not tried. Checked in the sandbox: full build without warnings, all device trees build, and the script's build stage on a tree prepared like the owner's. Not run on the Mac.

## Pushing to a kernel fork from a shallow clone
GitHub answers "have" for commits of the whole fork network, so with `push.negotiate=true` a branch based on an Asahi commit was pushed to a fork that only had `master` at v6.14-rc3, from a depth-1 clone, as a pack of just the new commits (2026-10-11). Creating the ref through the API is not possible from the assistant's sandbox.

## Kernel and device trees must be switched together
Owner report, 2026-10-11: the stock 7.1.13 kernel, booted while the trial kernel's device trees were installed, hung and did not detect a USB keyboard; the trial kernel on the same device trees was fine. The device trees are part of `m1n1/boot.bin` (built by `update-m1n1` from whatever `/boot/dtb` points at), so there is one set per boot, not one per GRUB entry, and a raw dtb loaded by GRUB would miss m1n1's fix-ups. Fedora's `10-devicetree.install` assumes a newer device tree is always safe for an older kernel; that does not hold between Asahi 7.1 and `asahi-wip-7.2`. Cause, from the journal of the hung boot (it ran on the first trial device trees, before the PCIe nodes existed): the stock display driver logs `apple-dcp 2289c00000.dcp: ... Failed to created PIODMA iommu child device` and then dereferences NULL in `apple_rtkit_start_ep` from `dcp_start`, so the graphical boot never comes up. Decision: `tbt-kernel.sh try` and `stock` switch the default kernel and the device trees together and there is no one-shot boot any more; `install` leaves whichever of the two was active.

## What is inside the enclosure
macOS, 2026-10-11: root port, then ASMedia `1b21:2463` upstream and downstream bridges, then one Realtek `10ec:9100` AHCI controller (class 010601) with eight 18 TB SATA disks. So Linux needs nothing beyond the PCIe host: the stock `ahci` driver covers the rest. Physically (the owner, 2026-10-17): the ASM2464PD sits on a vertical board that takes the USB-C cable from outside, with the 9-port SATA controller attached behind it (Linux: "9/9 ports implemented", PCIe 8 GT/s x2); how the two connect is not known. The SATA wires inside are about 15 cm; the USB-C cables to the Mac are 1 m.

## No backport to 7.1
Superseded on 2026-10-11 by [The 7.1 backport](#the-71-backport): the GPU driver is missing on 7.2, which changed the weighing.

## Asahi does not take LLM work (kernel notes)
Policy read 2026-10-11: generative AI is forbidden for material contributions; LLM-drafted issues may be closed; using an LLM on m1n1 hypervisor traces is listed as a violation; concealment leads to a ban. Decision: publish in this repository and the owner's fork, always disclosed. Any report to Asahi is written by the owner.

## The 7.1 kernel on the Mac: results and the read ceiling
Owner's boot dump, capture and bench of 2026-10-11, kernel `7.1.13-tbtwip` (`tbt/7.1` at `9d460b403164`). Verified: the GPU driver binds (`Initialized asahi 0.0.0`, G14D, 76 active cores), no deferred devices, no failed units, six controllers with their tuning data on all six ports. Plug-in: link up 1.1 s after the cable, eight disks about 22 s later (spin-up, `softreset failed (device not ready)` meanwhile is normal). Eject, unplug, replug: `Tunnel error`, `stopping tunnel`, `failed to stop engine (-19)`, then a clean second enumeration with eight disks; no IOMMU fault in either round.

Reads with `dd` and direct I/O, 4 GiB each: one disk at a time 267 to 287 MB/s (the platters), all eight together 211 MB/s each, 1.69 GB/s in total. The ceiling is inside the enclosure: its SATA controller's PCIe link is 8 GT/s x2 (its maximum, `LnkCap` and `LnkSta` agree), about 1.97 GB/s before packet overhead, while the USB4 link carries 2 x 20 Gb/s. Nothing on the Mac side limits sequential reads.

One new warning at boot, `WARNING: drivers/base/core.c:1504 at __device_links_no_driver`, for `2702280000.usb` (same device pointer as the "late IOMMU probe" warning two lines earlier): the USB controller's probe was deferred while the `apple_dart` module was still probing the IOMMU that had just attached to it. The port works afterwards (the keyboard is on it). Inferred to be a timing variant of the "late IOMMU probe" warning the stock kernel also prints; not seen in three 7.2 boots, and no clean stock boot dump exists yet to compare.

## What macOS the m1n1 hypervisor wants
Asahi's hypervisor guide, read 2026-10-13: supported guests are macOS 13.5 (M1 and M2 series) and 14.8.3 (M1 to M3); other versions are explicitly not supported and 15 or later is not mentioned. The guest is a second macOS on its own volume inside the existing macOS container ("Create a second Volume on your macOS partition"), not a partition of its own, so it needs no room in the partition table. Only when tracing starts is that volume's security lowered from recovery (`bputil -nkcas`, `csrutil disable`) and m1n1 installed as its boot object with `kmutil configure-boot`; a host computer on the DFU port drives it. A Kernel Debug Kit is optional. 13.5 is also the firmware version Linux runs here (`os-fw-version: 13.5` in the boot dumps), so a 13.5 guest talks to the same firmware interfaces. Whether the M2 Ultra itself has been run under the hypervisor is not stated there. Getting the installer, 2026-10-13: `softwareupdate` on the owner's Mac offers neither 13.5 nor 14.8.3 (only 14.8.7 to 14.8.9 of that line), and Apple's own package URL for 13.5 (22G74) answers 403. The guide's fallback is an archived `InstallAssistant.pkg` (archive.org items `install-assistant_20240930` for 13.5, `install-assistant_20250207` for 14.8.3); being a third-party copy, its Apple signature is checked with `pkgutil --check-signature` before it is run.
- ANE stage 0 (cell 4414, 27 Oct, omarchy-ane-probe from the linux-ane fork at ae18911): soc t6022, no ANE node in
  the running kernel's device tree (ane_nodes empty: the overlay is needed), the die-1 bus soc@2200000000 is there,
  the macOS stub firmware is 13.5, the version omarchy-ane's M2 firmware pin is for. Root-only parts (genpd, dmesg)
  were not read.
- Running cells, 27 Oct: GPU benchmarks take ~/.cache/linux-lab-gpu.lock (flock) so two never share the GPU (4416
  and 4422 ran together and their numbers are void); a cell must not stop processes with pkill -f on a pattern its
  own command line contains (4417 and 4423 killed themselves): match by process name, then by /proc/PID/cmdline.
  Dependent steps go in one chain (propose_run after=CELL).
- The series' head of 25 Oct (cell 4427, alone under the GPU lock): nextperf (9323171c + agxperf) against agxperf
  (795ae42a71 + agxperf), both offering cooperative matrices: Llama 2 7B pp512/tg64 760.3/64.9 against 763.1/64.9,
  Qwen Coder Q8 pp512/pp2048/tg64 486.4/782.4/32.1 against 486.1/781.3/31.8; MUL_MAT 2272/2272 and ARGMAX 7/7 pass on
  both. No speed in it for us; agxperf stays. The halved numbers of 4422 came from running beside 4416. MUL_MAT_ID
  printed no result line on either driver in the production build: open.
- MUL_MAT_ID with llama-run.sh's settings (cells 4441, 4444): GGML_VK_MMV_ID_MAX=64 aborted the production build's
  test on GGML_ASSERT(allow_misalign || misalign_bytes == 0), the duplicate-id case whose expert ids are a view 4
  bytes into their tensor (that case is under #if 0 in 2280f0f, so llama.cpp-up never ran it). With honeykrisp 0002
  keeping offset views on the matmul path: 955/955 pass with both settings, Qwen t/s at 8 9 16 32 48 64 512 tokens
  105 107 114 96 123 143 483, as before.
