"""make_lab.py SRC OUTDIR: the lab's two copies of drivers/soc/apple/pmp.rs for the M2 Ultra.

pmp_lab.rs     binds only "apple,t6020-pmp-v2"; logs every PMP boot argument as it finds it (before the patch, so
               BDID and DVID log 0); patches BDID and DVID only (Asahi's
               own M2-family path, m1n1 proxyclient/experiments/pmp_init.py since 1193477: DCAP and the IOVA
               table on T600X only; the driver already answers an empty table when apple,pio-ranges is absent);
               numbers its AdvertiseAcks as macOS does (below)
pmp_lab_ro.rs  the same, but read only: logs the boot arguments, writes nothing, never starts the PMP, and refuses
               the device (ENODEV) so the driver can be unloaded and the real one loaded after it
Every replacement must apply exactly once."""
import sys

src = open(sys.argv[1]).read()


def sub(s, old, new):
    assert s.count(old) == 1, old[:60]
    return s.replace(old, new)


s = sub(src, 'const PIO_GRANULARITY: u64 = 0x1000000;\n',
        'const PIO_GRANULARITY: u64 = 0x1000000;\n'
        '/// Lab build: log the boot arguments and stop before writing anything (pmp_lab_ro).\n'
        'const READ_ONLY: bool = @RO@;\n')
s = sub(s, '            idx += 8;\n',
        '            idx += 8;\n'
        '            {\n'
        '                let k = key.to_be_bytes();\n'
        '                let n = core::cmp::min(size, 8);\n'
        '                dev_info!(self.dev, "boot argument {}{}{}{}: {} bytes, first {:?}\\n", k[0] as char, k[1] as char,\n'
        '                    k[2] as char, k[3] as char, size, &arg_bytes[idx..idx + n]);\n'
        '            }\n')
s = sub(s, '        io.try_memcpy_toio(offset, &arg_bytes)\n',
        '        if READ_ONLY {\n'
        '            return Ok(());\n'
        '        }\n'
        '        io.try_memcpy_toio(offset, &arg_bytes)\n')
# probe: BDID and DVID only, and the read-only stop before the PMP CPU is started
i = s.index('        match node.property_read(c"apple,dram-capacity").optional() {')
j = s.index('        let rtkit = rtkit::RtKit::<PmpData>::new(')
s = s[:i] + ('        // No DCAP on t602x: Asahi\'s M2-family init sets BDID and DVID only.\n'
             '        data.patch_bootargs(pdev, &[(from_fourcc(b"BDID"), bdid), (from_fourcc(b"DVID"), dvid)])?;\n'
             '        if READ_ONLY {\n'
             '            dev_info!(dev, "read only: nothing written, PMP not started\\n");\n'
             '            return Err(ENODEV);\n'
             '        }\n') + s[j:]
# AdvertiseAck as macOS sends it (4 Nov trace, 794 of them): indices from 0, and a name the tree does not hold is
# answered INDEX 0 SIZE 0 without taking an index. Upstream numbers from 1 and spends an index on a miss, and its
# SetVal handler reads entry INDEX of a list that starts at 0, so the last entry is out of range.
s = sub(s, '        state.ioreg_entries.push(size, GFP_KERNEL)?;\n        let index = state.ioreg_entries.len() as u64;\n',
        '        if size == 0 {\n'
        '            return Ok((OPC_REGISTER_IOREG | OPC_ACK_MASK) << OPC_SHIFT);\n'
        '        }\n'
        '        let index = state.ioreg_entries.len() as u64;\n'
        '        state.ioreg_entries.push(size, GFP_KERNEL)?;\n')
s = sub(s, '[(of::DeviceId::new(c"apple,t6000-pmp-v2"), ())]', '[(of::DeviceId::new(c"apple,t6020-pmp-v2"), ())]')
s = sub(s, '    name: "apple_pmp",\n    description: "Apple Power Management Processor",',
        '    name: "@NAME@",\n    description: "Apple Power Management Processor (lab copy for t6022)",')
out = sys.argv[2]
for name, ro in (("pmp_lab", "false"), ("pmp_lab_ro", "true")):
    open(f"{out}/{name}.rs", "w").write(s.replace("@RO@", ro).replace("@NAME@", name))
open(f"{out}/Kbuild", "w").write("obj-m += pmp_lab.o pmp_lab_ro.o\n")
print("wrote", out, "pmp_lab.rs pmp_lab_ro.rs")
