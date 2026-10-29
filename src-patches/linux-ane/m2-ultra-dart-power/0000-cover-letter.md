dt: t6022: the ANE DARTs in ANE_SYS, so an M2 Ultra boots with the overlay

The shipped `t6022-ane` overlay panics an M2 Ultra (Mac Studio 2023, J475d) at boot: an asynchronous SError in
`apple_dart_probe` 2.66 s in, on about ten boots out of eleven. The overlay puts ANE dart0 in pmp and dart1/2 in
ANE_CPU. On the same machine, macOS 15's IORegistry gives `dart-ane0` (all three DART windows) power gate 0x1fb,
`ANE-SYS-DART`, whose parent is `ANE_SYS` (pmgr 0x260), which iBoot leaves off: dart0 was being read with its power
island down.

This change gives the three DARTs `power-domains = <&ps_ane_sys>` in `packaging/dt/t6022-ane.dts` only (t6020 and
t6021 keep the shared values) and adds the receipt `receipts/2026-10-29-t6022-j475d-ane-sys/`.

Results on the J475d, kernel 7.1.13 (linux-asahi 7.1.13-3 base), `ane_t6021` at ae18911:

- Boot clean; the three DARTs initialize; `284000000.ane` joins iommu group 0.
- Firmware `t602x_ane0_fw_selene_rc4x` (the 13.5 pin) boots, handshake complete, channel table validated,
  `/dev/accel/accel0`.
- `omarchy-ane-smoke` add-fixture: 20/20 calls bit-exact against the golden sha256, min 0.398 ms, median 0.418 ms
  (29 Oct 01:36).
- Reproduced on a later boot of a rebuilt kernel the same day (29 Oct 07:01): firmware boot and channel table again,
  `state HELD`, BO cap 12288 MiB.

Not covered: the second die's Neural Engine (`dart-ane1` at 0x2285800000, power gate 0x100001fb, the same layout
one die up), and anything beyond the smoke fixture.

How the overlay was applied: dtc 1.7.2; every phandle in the result resolved. dtc 1.7.0's fdtoverlay gives a node the
overlay labels a new phandle and leaves the node's other users dangling (seen on a synthetic tree), so 1.7.1 or later
is needed for this overlay.

The macOS data the fix was read from (device tree, IORegistry power tables, firmware hashes of macOS 13.7.8, 14.8.9
and 15.8.1) is public: https://github.com/Ophuscado/linux-lab/tree/master/results/macos
