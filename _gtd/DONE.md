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
