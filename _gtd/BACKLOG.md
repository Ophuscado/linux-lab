? Report the two driver bugs to Asahi in the operator's own words, disclosing LLM use · options: report, or keep local · default: operator decides later
Re-check asahi-wip-7.2 for the GPU driver being re-enabled and move the fixes over · check: DRM_ASAHI no longer depends on BROKEN at the new base
Install m1n1 1.9.9 for unique router IDs before attaching several enclosures · check: each domain's unique_id differs
Confirm the Bluetooth-after-suspend fault and pick a mitigation · check: journal shows hci0 command tx timeout after resume
Spin down the USB-A disks with hd-idle · check: hdparm -C reports standby after the idle time
Retry the PCIe controller when its tunnel comes up before its driver · check: enclosure attached at boot gets its disks without a replug
? Give each bus behind a tunnel its own IOMMU stream, as the 2023 tree did · options: per-bus streams (isolation between devices), or keep one shared stream (simpler) · default: keep one stream
Drop the DEBUG cable_info_or commit from the branch once cable handling is settled · check: branch builds and links without it
Share Bluetooth pairings between macOS and Linux with asahi-btsync · check: keyboard and mouse connect in both systems without pairing again
Survive pulling an enclosure without eject · check: unplug with disks attached leaves the system running and a replug brings them back; run it with netconsole to the second Mac so a freeze leaves a log
Find why the boot dump shows apple,tunable-pcie-adapter on two of the six ACIO nodes only · check: all six listed, or the reason is in KNOWLEDGE.md
