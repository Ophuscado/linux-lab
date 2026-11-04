"""img4-unpack.py SRC DST: a macOS kernelcache (an Image4 file) into the bare Mach-O m1n1's hypervisor boots.

The file is nested DER: IMG4 > IM4P (or a bare IM4P) > type, description, payload, optional compression info. The
payload is LZFSE ("bvx2"), which macOS's own libcompression decodes, so this needs no packages and runs on any macOS.
pyimg4 failed on 13.7.8's kernelcache, and img4tool needs autotools from Homebrew or MacPorts. This is the code the
operator ran from the stick as kernelcachedecoder.py on 4 Nov (96,763,904 bytes, magic cffaedfe, `file`: Mach-O 64-bit
arm64e), plus two checks that stop on a short decode or a payload that is not a 64-bit Mach-O; both give the same
bytes on test files. A payload that is not bvx2 is written as it is.
"""
import ctypes
import sys

src, dst = sys.argv[1], sys.argv[2]
d = open(src, "rb").read()


def tlv(i):
    """One DER element at i: its tag, where its value starts, the value's length."""
    tag, n = d[i], d[i + 1]
    i += 2
    if n & 0x80:
        k = n & 0x7F
        n = int.from_bytes(d[i:i + k], "big")
        i += k
    return tag, i, n


def kids(v, n):
    i, out = v, []
    while i < v + n:
        t, vv, nn = tlv(i)
        out.append((t, vv, nn))
        i = vv + nn
    return out


_, v, n = tlv(0)
top = kids(v, n)
magic = d[top[0][1]:top[0][1] + top[0][2]]
im4p = kids(top[1][1], top[1][2]) if magic == b"IMG4" else top
print("container", magic, "payload type", d[im4p[1][1]:im4p[1][1] + im4p[1][2]])
_, pv, pn = im4p[3]
payload = d[pv:pv + pn]
size = None
if len(im4p) > 4 and im4p[4][0] == 0x30:  # compression info: algorithm, uncompressed size
    c = kids(im4p[4][1], im4p[4][2])
    size = int.from_bytes(d[c[1][1]:c[1][1] + c[1][2]], "big")
print("payload", len(payload), "bytes, starts", payload[:4], "uncompressed size", size)
if payload[:4] == b"bvx2":
    lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
    f = lib.compression_decode_buffer
    f.restype = ctypes.c_size_t
    f.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    buf = ctypes.create_string_buffer(size or 512 * 1024 * 1024)
    got = f(buf, len(buf), payload, len(payload), None, 0x801)  # COMPRESSION_LZFSE
    if not got or (size and got != size):
        sys.exit(f"LZFSE decode gave {got} bytes, expected {size}")
    payload = buf.raw[:got]
open(dst, "wb").write(payload)
print("wrote", dst, len(payload), "bytes, magic", payload[:4].hex())
if payload[:4] != bytes.fromhex("cffaedfe"):
    sys.exit("not a 64-bit Mach-O")
