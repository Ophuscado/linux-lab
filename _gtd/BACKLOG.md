? Report the two driver bugs to Asahi in the operator's own words, disclosing LLM use · options: report, or keep local · default: operator decides later
Re-check asahi-wip-7.2 for the GPU driver being re-enabled and move the fixes over · check: DRM_ASAHI no longer depends on BROKEN at the new base
Install m1n1 1.9.9 for unique router IDs before attaching several enclosures · check: each domain's unique_id differs
? Give each bus behind a tunnel its own IOMMU stream, as the 2023 tree did · options: per-bus streams (isolation between devices), or keep one shared stream (simpler) · default: keep one stream
Drop the DEBUG cable_info_or commit from the branch once cable handling is settled · check: branch builds and links without it
Let the USB4 link to the enclosure use its low-power states, which the log shows as supported on one end only · check: capture shows CLx enabled and idle power with the enclosure attached drops below 27 W
Four-finger trackpad gestures need a longer swipe than three-finger ones · check: threshold found in KWin source and a local patch or a setting; no setting exists today
After the migration: data maintenance on the pool: mergerfs.dedup/consolidate/balance (mergerfs-tools), per-disk duperemove (XFS reflinks), xfs_fsr; check: snapraid sync clean afterwards
Find rsync temp files that killed copies left in the pool: temp-like names (.name.XXXXXX) that no source holds; never by name alone, sources hold such files themselves · check: list from a comparison with the sources, nothing moved without a look
? Let the row copies start at once instead of after a full listing (drop --no-inc-recursive from migrate-row.sh) · options: drop it (progress total grows as the listing goes, a restart copies at once), or keep it (exact total, listing first) · default: keep
? Power-cycle a box from the script when its controller stops answering (today only an unplug or a reboot does it) · options: power the ASM2464 board from the box supply and put each box on a switchable plug the script drives, or keep it manual · default: manual
