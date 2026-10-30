# kernel

Kernel changes for the Mac Studio (M2 Ultra, `j475d`) on Fedora Asahi Remix, and the scripts that build and try
them beside the stock kernel. The series are in [`../src-patches/linux/`](../src-patches/linux/), each on a pinned
commit (`BASE`); `../publish.sh` turns one into a branch of https://github.com/Ophuscado/linux. None is submitted
upstream yet: Asahi does not take AI-assisted patches, and mainline wants each series rewritten in its form first.

| Series | What it does | State |
|---|---|---|
| `tbt-7.1` | USB4/Thunderbolt with PCIe tunnels on Asahi's 7.1.13 (the stock kernel's source): the 7.2 USB4 stack backported, the tunneled PCIe controller, DART address offsets, device trees | Running; verified with USB4 (ASM2464, until 21 Oct) and Thunderbolt 3 boxes (two M424: Titan Ridge + SAS3008) |
| `tbt-pcie` | The same work as first written on Asahi's 7.2 work-in-progress tree, which has no GPU driver | Reference for upstream |
| `asahi-fdinfo` | Per-client GPU memory and time in fdinfo for the Rust `asahi` driver | Running; busy time needs `asahi.busy_stats=1` (patch 3) |
| `hid-magicmouse` | Magic Mouse: no scroll from a resting finger (`scroll_hold_ms`), two-finger double tap zoom (`smart_zoom`, off: to become the screen zoom) | Running, `magicmouse.sh hold 1` |
| `hid-apple` | Magic Keyboard: Fn+F, C, P, D as their own keys (`fn_shortcuts`) | Running, `applekbd.sh try` |

Neural Engine: `dt/t6022-ane-dart-power.dts` puts the M2 Ultra's ANE DARTs in `ANE_SYS` (merged into omarchy-ane);
`ane.sh` builds and loads omarchy-ane's driver by hand and runs omarchy-mlx's collector for the judged row (`deep`).

## Use

    ./tbt-kernel.sh deps && ./tbt-kernel.sh build && ./tbt-kernel.sh install    # then reboot
    ./tbt-kernel.sh status      # what the running kernel sees
    ./tbt-kernel.sh previous    # back to the kernel installed before
    ./tbt-kernel.sh stock       # back to Fedora's kernel and device trees

The device trees live in m1n1's boot image, so kernel and device trees are always switched together; the stock kernel
hangs on the trial device trees. The script's header lists every stage and how to recover from macOS.

Tools: `tbt-capture.sh` records enclosure plug-ins with driver debugging on; `boot-dump.sh` writes what a kernel
brought up, to compare kernels; `apciec-dump.sh` (in macOS) dumps the tunnel controller there; `magicmouse.sh` and
`applekbd.sh` set the HID patches' parameters on a kernel built with them, now and at every boot, or build them as
modules against a kernel without them.

## License

GPL-2.0-only, the kernel's.
