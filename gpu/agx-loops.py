#!/usr/bin/env python3
"""agx-loops.py: the innermost loops of AGX GPU code, with their instruction mix: what a loop spends per matrix op or
per load, and where its waits fall after its loads.

  agx-loops.py mesa DUMP [N]                  Mesa's final code (AGX_MESA_DEBUG=shaders output of any Vulkan program)
  agx-loops.py metal APPLEGPU FUNCTIONS [OFF]  Apple's compiled kernels: functions.data of a Metal shader cache, its
                                              Mach-O images disassembled with dougallj/applegpu (a clone at APPLEGPU);
                                              OFF: image offsets in hex, default every image

Per shader it prints the N (default 2) smallest loops that hold a matrix op (simd_matrix_*) or, failing that, at
least 4 device loads, and for a load loop the order of loads (L), waits (W) and local loads (l). A loop is the range
of a backward branch. Mesa's disassembler leaves some instructions undecoded ("XXX"); counts are then lower bounds.
"""
import collections, contextlib, io, re, struct, sys

INS = re.compile(r'^\s*([0-9a-f]+):\s+[0-9a-f]+(?: [0-9a-f]+)*\s+(\S+)\s*(.*)$')
LOADS = ('load', 'device_load')


def parse(text):
    """Instruction lists, one per program: a new one starts where the offsets go back."""
    blocks, cur = [], []
    for line in text.split('\n'):
        m = INS.match(line)
        if not m:
            continue
        off = int(m.group(1), 16)
        if cur and off <= cur[-1][0]:
            blocks.append(cur)
            cur = []
        cur.append((off, m.group(2), m.group(3)))
    if cur:
        blocks.append(cur)
    return blocks


def loops_of(block):
    """(start, end) of every backward branch: Mesa prints a relative byte offset, applegpu an absolute address."""
    out = []
    for off, mn, args in block:
        if not mn.startswith('jmp'):
            continue
        args = args.strip()
        rel, ab = re.match(r'(-\d+)', args), re.match(r'0x([0-9a-fA-F]+)', args)
        if rel:
            out.append((off + int(rel.group(1)), off))
        elif ab and int(ab.group(1), 16) < off:
            out.append((int(ab.group(1), 16), off))
    return out


def report(tag, block, n):
    found = []
    for lo, hi in loops_of(block):
        seg = [i for i in block if lo <= i[0] <= hi]
        mat = sum('simd_matrix' in i[1] for i in seg)
        lds = sum(i[1] in LOADS for i in seg)
        if mat or lds >= 4:
            found.append((0 if mat else 1, len(seg), lo, hi, mat, seg))
    for kind, size, lo, hi, mat, seg in sorted(found)[:n]:
        mix = ", ".join(f"{k} {v}" for k, v in collections.Counter(i[1] for i in seg).most_common(16))
        per = f", {size / mat:.1f} per matrix op" if mat else ""
        print(f"{tag} loop {lo:#x}-{hi:#x}: {size} instructions, {mat} matrix ops{per}; {mix}")
        if not mat:
            order = "".join('L' if i[1] in LOADS else 'W' if i[1] == 'wait' else 'l' if i[1] == 'lload' else '.' for i in seg)
            print(f"  order: {order}")


def macho_text(data, off):
    """The __text section of the 64-bit Mach-O image at off, or None."""
    try:
        _, _, _, _, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', data, off)
    except struct.error:
        return None
    p = off + 32
    for _ in range(min(ncmds, 64)):
        cmd, size = struct.unpack_from('<II', data, p)
        if cmd == 0x19:  # LC_SEGMENT_64
            for k in range(struct.unpack_from('<I', data, p + 64)[0]):
                s = p + 72 + 80 * k
                if data[s:s + 16].rstrip(b'\0') == b'__text':
                    tsz = struct.unpack_from('<Q', data, s + 40)[0]
                    toff = struct.unpack_from('<I', data, s + 48)[0]
                    return data[off + toff:off + toff + tsz]
        if not size:
            break
        p += size
    return None


def main(argv):
    if len(argv) >= 2 and argv[0] == 'mesa':
        n = int(argv[2]) if len(argv) > 2 else 2
        for i, b in enumerate(parse(open(argv[1], errors='ignore').read())):
            report(f"shader {i} ({len(b)} instructions)", b, n)
    elif len(argv) >= 3 and argv[0] == 'metal':
        sys.path.insert(0, argv[1])
        import disassemble as D  # dougallj/applegpu
        D.STOP_ON_STOP = False
        data = open(argv[2], 'rb').read()
        offs = [int(x, 16) for x in argv[3:]] or [m.start() for m in re.finditer(rb'\xcf\xfa\xed\xfe', data)]
        for off in offs:
            text = macho_text(data, off)
            if not text:
                continue
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                D.disassemble(text)
            for b in parse(buf.getvalue()):
                report(f"image {off:#x}", b, 2)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
