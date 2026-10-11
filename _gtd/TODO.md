Spin down the USB-A disks with hd-idle · check: hdparm -C reports standby after the idle time
Eject the enclosure before suspend and attach it again after resume · check: suspend and resume with the enclosure attached, eight disks back, no error in the kernel log
Confirm the Bluetooth-after-suspend fault and pick a mitigation · check: journal shows hci0 command tx timeout after resume
Ship the settings above as one installer of udev rules and systemd units, with an uninstall · check: settings hold after a reboot and a replug; uninstall leaves no file behind
Survive pulling an enclosure without eject · check: unplug with disks attached leaves the system running and a replug brings them back; run it with netconsole to the second Mac so a freeze leaves a log
Reproduce the replug freeze with netconsole attached · check: ten eject, unplug, replug rounds without a freeze, or the log of one
Power down the Thunderbolt PCIe controllers that have no tunnel, if the power dump shows they cost power · check: ps_atcN_pcie off in the power-domain summary with nothing attached and on with a tunnel, idle power lower
Load a model larger than the GPU memory the driver reports · check: all layers on the GPU, no allocation failure
