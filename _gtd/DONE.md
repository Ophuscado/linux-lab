Find why USB4 enclosures are invisible on stock 7.1.13 · check: dmesg shows the USB4 pipehandler fallback line on plug-in
Build and boot asahi-wip-7.2 next to the stock kernel · check: uname -r is 7.2.2-tbtwip and the stock kernel stays default
Fix the 20 Gb/s cable flag for cable speeds above 3 · check: capture shows LOCAL gen=2, lanes enter CL0, device 0-1 found
Reinitialise USB when a partner leaves USB4 without unplugging · check: lsusb -t shows the ASM246X at 10000M
Collect the macOS description of the Thunderbolt PCIe controller · waits: operator runs apciec-dump.sh in macOS and returns ~/apciec.txt
Decide the apciec driver approach from apciec.txt · check: compatible and reg layout compared with pcie-apple.c, result in KNOWLEDGE.md
Push this repository and branch tbt/usb4-fixes to github.com/Ophuscado/linux-lab and /linux · check: git ls-remote shows main and tbt/usb4-fixes at the local tips
Push branch tbt/usb4-fixes to the fork and build from it in tbt-kernel.sh · check: build stage fetches the fork branch and the embedded patch is gone
