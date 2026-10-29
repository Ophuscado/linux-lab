#!/usr/bin/env python3
"""gguf-meta.py: the string metadata of GGUF files and their sizes, without numpy or llama.cpp.

    python3 -I macos/gguf-meta.py FILE...      one block per file: size, then every string key
                                               (general.name, general.repo_url, general.quantized_by, ...)

Reads only the header (keys and values, up to the tensor infos); arrays are summarized by type and length.
Used to tell which published repository a local model came from, so a machine without the copy can fetch
the same file.
"""
import os
import struct
import sys

# GGUF value types (gguf.h): 0 u8, 1 i8, 2 u16, 3 i16, 4 u32, 5 i32, 6 f32, 7 bool, 8 string, 9 array,
# 10 u64, 11 i64, 12 f64
FIXED = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}


def read(f, fmt):
    n = struct.calcsize("<" + fmt)
    b = f.read(n)
    if len(b) != n:
        raise EOFError("header ends early")
    return struct.unpack("<" + fmt, b)[0]


def string(f):
    n = read(f, "Q")
    if n > 1 << 24:
        raise ValueError(f"string of {n} bytes: not a GGUF header")
    return f.read(n).decode("utf-8", "replace")


def value(f, t):
    if t in FIXED:
        return read(f, FIXED[t])
    if t == 8:
        return string(f)
    if t == 9:
        et, n = read(f, "I"), read(f, "Q")
        for _ in range(n):  # skipped, but read to stay in step
            value(f, et)
        return f"<array of {n} type {et}>"
    raise ValueError(f"unknown value type {t}")


def meta(path):
    with open(path, "rb") as f:
        if f.read(4) != b"GGUF":
            raise ValueError("not a GGUF file")
        version = read(f, "I")
        tensors, kvs = read(f, "Q"), read(f, "Q")
        out = {"gguf.version": version, "tensors": tensors}
        for _ in range(kvs):
            k = string(f)
            out[k] = value(f, read(f, "I"))
        return out


def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    rc = 0
    for p in argv:
        print(f"== {p}")
        print(f"  size: {os.path.getsize(p)}")
        try:
            for k, v in meta(p).items():
                if isinstance(v, str) and not v.startswith("<array") and len(v) < 400 or k in ("gguf.version", "tensors", "split.count", "split.no"):
                    print(f"  {k}: {v}")
        except (ValueError, EOFError, OSError) as e:
            print(f"  ERR: {e}")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
