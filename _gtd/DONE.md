Find why USB4 enclosures are invisible on stock 7.1.13 · check: dmesg shows the USB4 pipehandler fallback line on plug-in
Build and boot asahi-wip-7.2 next to the stock kernel · check: uname -r is 7.2.2-tbtwip and the stock kernel stays default
Fix the 20 Gb/s cable flag for cable speeds above 3 · check: capture shows LOCAL gen=2, lanes enter CL0, device 0-1 found
Reinitialise USB when a partner leaves USB4 without unplugging · check: lsusb -t shows the ASM246X at 10000M
Collect the macOS description of the Thunderbolt PCIe controller · waits: operator runs apciec-dump.sh in macOS and returns ~/apciec.txt
Decide the apciec driver approach from apciec.txt · check: compatible and reg layout compared with pcie-apple.c, result in KNOWLEDGE.md
Push this repository and branch tbt/usb4-fixes to github.com/Ophuscado/linux-lab and /linux · check: git ls-remote shows main and tbt/usb4-fixes at the local tips
Push branch tbt/usb4-fixes to the fork and build from it in tbt-kernel.sh · check: build stage fetches the fork branch and the embedded patch is gone
Switch kernel and device trees together in tbt-kernel.sh · check: try, stock, install and status dry-run against stubs end with matching kernel and device trees
Add device-tree nodes for the six apciec controllers and their IOMMUs on t602x · check: dtb builds and the nodes are present and enabled under /proc/device-tree
Give pcie-apple.c a single-port tunnel variant without reset GPIO or reference clock · check: driver binds and root port 106b:1014 shows in lspci
Bring the PCIe link up when the Thunderbolt tunnel is active · check: the two ASMedia 1b21:2463 bridges enumerate
Find what makes the stock kernel hang on the trial device trees · check: the failing driver or node is named in KNOWLEDGE.md
Survive unplugging and replugging an enclosure · check: capture round 2 (eject, unplug, plug) completes and the PCI devices come back
Find what keeps the GPU driver broken on asahi-wip-7.2 · check: the compile errors with "depends on BROKEN" removed are listed in KNOWLEDGE.md, with an estimate of the port
Backport the Thunderbolt core changes and the Apple USB4 driver to asahi-7.1.13-3 · check: branch tbt/7.1 builds thunderbolt_apple.ko with the Fedora-like config
Backport the Type-C Thunderbolt switch, tipd, atcphy USB4 and CIO reset changes to tbt/7.1 · check: tps6598x, phy-apple-atc and reset-apple-cio build
Add the USB4 and tunneled PCIe device-tree nodes to the 7.1 device trees without touching the display nodes · check: all Apple device trees build and the DCP nodes are byte-identical to the stock ones
Apply the lab's nine commits to tbt/7.1 · check: pcie-apple and apple-dart build, module and built in
Let tbt-kernel.sh build tbt/7.1 with the GPU driver kept · check: build stage ends without TBT_NO_GPU and DRM_ASAHI stays m
Run the tbt/7.1 kernel on the Mac: GPU and Thunderbolt disks on one kernel · check: boot dump shows the asahi GPU module loaded and the capture shows the eight disks · waits: operator builds 9d460b403164, attaches the boot-dump and tbt-capture files
Find why the boot dump shows apple,tunable-pcie-adapter on two of the six ACIO nodes only · check: all six listed, or the reason is in KNOWLEDGE.md
Route DMA through the port IOMMU and deliver MSIs · check: ahci binds to 10ec:9100 and the eight disks appear, mounted read-only · waits: operator runs tbt-kernel.sh mount and bench and pastes the output
Measure llama.cpp on the CPU and through Vulkan · check: llama-bench tables for both in the llama-bench file · waits: operator runs llama-bench.sh with a model on a kernel that has the GPU driver
Record the power and tuning state with and without the enclosure · check: two power-dump files with sensor readings, link power states and disk settings · waits: operator runs power-dump.sh idle with the enclosure attached and again without it, attaches both files
Name the operations that make up the Vulkan gap from the timings in the llama-bench file · check: the five largest by time with their share in KNOWLEDGE.md
Share Bluetooth pairings between macOS and Linux with asahi-btsync · check: keyboard and mouse connect in both systems without pairing again · waits: operator pairs the devices in macOS, boots Linux, runs bt-sync.sh and reports whether they connect in both
Bring a fresh install to the lab state with setup.sh, with a snapshot to return to · check: after setup.sh all and a reboot, tbt-kernel.sh status shows the trial kernel, and setup.sh list shows the clean snapshot · waits: operator reinstalls Fedora Asahi, runs setup.sh all, reports what it printed
Inventory the 32 disks: enclosure, slot, serial, volume, fill · check: disk-inventory.txt lists 32 disks with the empty one of each row at slot 7 · waits: operator powers the boxes on, replugs the two enclosures that fell back to USB, runs disk-inventory.sh
Authorize USB4 devices by udev rule so all four enclosures get tunnels · check: status lists 32 sata disks after a boot with the boxes attached and after replugs · waits: operator runs tbt-kernel.sh authorize on, replugs, reboots once with the boxes on
? Filesystem for the data disks · options: XFS on all 32 (one tool set, parity needs it anyway), or ext4 on data and XFS on parity · default: XFS on all
Magic Mouse and middle-click paste on KDE · check: after ux-fix.sh on and a re-login, a centre click is left or right, a resting finger does not scroll, middle click pastes nothing · waits: operator runs ux-fix.sh on, reports
Make recheck fast enough to wait for · check: two-row loop test finds the short copy and the double by size in under a second, the flipped byte with VERIFY=full
Keep the row workers alive when a pool disk dies · check: loop test with a branch shut down before and during a copy: the worker drops it, finishes, all 18 checksums match, 'good' puts it back
One command restarts every ended or missing worker, one shows the dropped disks and link errors · check: loop test, start with no row replaces the ended D worker and starts the rest; status lists a missing disk and maps ata ports to disk names on a fake sysfs
Put disk 15 back into the pool with good 15, as the operator chose: its log replays at the mount, and a short copy left on it by a crash fails its source's verify (sizes), so nothing is formatted on a bad copy · check: the pool lists 15 and takes a write on it · waits: operator runs good 15 and returns the pool and links
Reach the operator's panel from the agent session for supervised commands · check: tools/list answers through a connector · waits: operator adds the panel as a custom connector (the sandbox refused a direct call with the token) and rotates the token that was pasted in chat
Do not mark a source verified by size when a pool branch logged a write I/O error during its copy: XFS keeps the written size in memory, so a copy whose data never reached the disk passes a size check; workers started before fc613c1 do not fsync either · check: loop test with a write error logged for a branch during a copy: the worker stops before marking the source, the source untouched
Bring 15 back into the pool once box C is fixed: migrate-row.sh aside 15 "2026-10-16 21:33" first (its write I/O errors at 22:03:45 came while no worker watched for them), then good 15 · check: the aside line in heal.log and the pool lists 15 · waits: box C fixed (the line above)
Find what took box C down on 16 Oct at 04:27: DART, PCIe or AER errors for domain 000a in the saved kernel log of that boot, or none · check: the answer in KNOWLEDGE.md
Set aside 15's copies from its two lost-write windows of 16 Oct that were never rechecked, while the rows copy on: migrate-row.sh aside 15 "2026-10-16 03:58" "2026-10-16 04:35" and aside 15 "2026-10-16 13:46" "2026-10-16 14:25" · check: two aside lines in heal.log, no source undone or formatted · waits: operator approves the panel cell
