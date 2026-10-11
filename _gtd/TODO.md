Tune the enclosure disks from the power dump and bench: scheduler, read-ahead, SATA link power, spin-down time · check: bench no slower than before, disks report standby after the idle time, idle power in the dump lower
Spin down the USB-A disks with hd-idle · check: hdparm -C reports standby after the idle time
Eject the enclosure before suspend and attach it again after resume · check: suspend and resume with the enclosure attached, eight disks back, no error in the kernel log
Confirm the Bluetooth-after-suspend fault and pick a mitigation · check: journal shows hci0 command tx timeout after resume
Ship the settings above as one installer of udev rules and systemd units, with an uninstall · check: settings hold after a reboot and a replug; uninstall leaves no file behind
Survive pulling an enclosure without eject · check: unplug with disks attached leaves the system running and a replug brings them back; run it with netconsole to the second Mac so a freeze leaves a log
Reproduce the replug freeze with netconsole attached · check: ten eject, unplug, replug rounds without a freeze, or the log of one
Power down the Thunderbolt PCIe controllers that have no tunnel, if the power dump shows they cost power · check: ps_atcN_pcie off in the power-domain summary with nothing attached and on with a tunnel, idle power lower
Compare Vulkan in Linux with Metal in macOS on the same model and llama.cpp commit · check: both llama-bench files, ratio per test in KNOWLEDGE.md
Name the operations that make up the Vulkan gap from the timings in the llama-bench file · check: the five largest by time with their share in KNOWLEDGE.md
Run llama.cpp on Mesa main built beside the system one and loaded with VK_DRIVER_FILES · check: one llama-bench table per Mesa, same generated text
? Try the third-party Honeykrisp cooperative-matrix series (omacom/mesa pull requests 3 to 6), not reviewed upstream and limited to M1 by its author · options: build it beside the system Mesa and test with an output check, or wait for upstream · default: build beside, system Mesa untouched
Tune llama.cpp matrix shaders and work-group sizes for this GPU, which gets generic settings today · check: tokens per second up on the same model, same generated text
Load a model larger than the GPU memory the driver reports · check: all layers on the GPU, no allocation failure
