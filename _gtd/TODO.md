Backport the Thunderbolt core changes and the Apple USB4 driver to asahi-7.1.13-3 · check: branch tbt/7.1 builds thunderbolt_apple.ko with the Fedora-like config
Backport the Type-C Thunderbolt switch, tipd, atcphy USB4 and CIO reset changes to tbt/7.1 · check: tps6598x, phy-apple-atc and reset-apple-cio build
Add the USB4 and tunneled PCIe device-tree nodes to the 7.1 device trees without touching the display nodes · check: all Apple device trees build and the DCP nodes are byte-identical to the stock ones
Apply the lab's nine commits to tbt/7.1 · check: pcie-apple and apple-dart build, module and built in
Let tbt-kernel.sh build tbt/7.1 with the GPU driver kept · check: build stage ends without TBT_NO_GPU and DRM_ASAHI stays m
