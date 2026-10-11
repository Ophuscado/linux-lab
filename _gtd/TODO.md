Push branch tbt/usb4-fixes to the fork and build from it in tbt-kernel.sh · check: build stage fetches the fork branch and the embedded patch is gone
Capture a replug on the kernel with both fixes · check: capture shows USB4 up, drop after 10 s, then SuperSpeed enumeration
Capture a stock-kernel boot dump and compare with the trial one · check: differences listed in KNOWLEDGE.md or none found
Add device-tree nodes for the six apciec controllers and their IOMMUs on t602x · check: dtb builds and the nodes are present and enabled under /proc/device-tree
Give pcie-apple.c a single-port tunnel variant without reset GPIO or reference clock · check: driver binds and root port 106b:1014 shows in lspci
Bring the PCIe link up when the Thunderbolt tunnel is active · check: the two ASMedia 1b21:2463 bridges enumerate
Route DMA through the port IOMMU and deliver MSIs · check: ahci binds to 10ec:9100 and the eight disks appear, mounted read-only
