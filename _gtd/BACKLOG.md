? Report the two driver bugs to Asahi in the operator's own words, disclosing LLM use · options: report, or keep local · default: operator decides later
Re-check asahi-wip-7.2 for the GPU driver being re-enabled and move the fixes over · check: DRM_ASAHI no longer depends on BROKEN at the new base
Install m1n1 1.9.9 for unique router IDs before attaching several enclosures · check: each domain's unique_id differs
? Give each bus behind a tunnel its own IOMMU stream, as the 2023 tree did · options: per-bus streams (isolation between devices), or keep one shared stream (simpler) · default: keep one stream
Drop the DEBUG cable_info_or commit from the branch once cable handling is settled · check: branch builds and links without it
Let the USB4 link to the enclosure use its low-power states, which the log shows as supported on one end only · check: capture shows CLx enabled and idle power with the enclosure attached drops below 27 W
