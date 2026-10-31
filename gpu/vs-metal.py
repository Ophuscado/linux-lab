#!/usr/bin/env python3
"""vs-metal.py HERE METAL... [--top N]: test-backend-ops perf timings on this system against Metal's, case by case.

HERE is a `test-backend-ops perf` output from Linux; METAL one or more from macOS (results/macos/*/ops-*.txt,
llama-ops-*.txt). Cases match on the op and its full parameter string. Prints per op the number of cases and the
geometric mean of HERE's time over Metal's, then the N (default 10) cases furthest behind and the 3 furthest ahead.
"""
import math, re, sys

CASE = re.compile(r'^\s*([A-Z_]+)\((.*?)\):\s+\d+ runs -\s+([0-9.]+) us/run')


def load(path):
    out = {}
    for line in open(path, errors='ignore'):
        m = CASE.match(line)
        if m:
            out[(m.group(1), m.group(2))] = float(m.group(3))
    return out


def main(argv):
    top = 10
    if '--top' in argv:
        i = argv.index('--top'); top = int(argv[i + 1]); del argv[i:i + 2]
    if len(argv) < 2:
        sys.exit(__doc__)
    here, metal = load(argv[0]), {}
    for f in argv[1:]:
        metal.update(load(f))
    rows = [(t / metal[k], k, t, metal[k]) for k, t in here.items() if k in metal]
    if not rows:
        sys.exit("no case in common")
    by = {}
    for r in rows:
        by.setdefault(r[1][0], []).append(r[0])
    for op, rs in sorted(by.items()):
        print(f"{op}: {len(rs)} cases, {math.exp(sum(map(math.log, rs)) / len(rs)):.2f}x Metal's time")
    rows.sort(reverse=True)
    print(f"furthest behind:")
    for ratio, (op, params), t, m in rows[:top]:
        print(f"  {ratio:6.2f}x {op}({params}): {t:.1f} / {m:.1f} us")
    print("furthest ahead:")
    for ratio, (op, params), t, m in rows[-3:]:
        print(f"  {ratio:6.2f}x {op}({params}): {t:.1f} / {m:.1f} us")


if __name__ == '__main__':
    main(sys.argv[1:])
