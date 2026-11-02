#!/usr/bin/env python3
"""bench-spread.py [--limit PCT] DIR...: how far apart the llama-bench step's t/s are across compare runs (sessions).

Each DIR is one gpu/llama-compare.sh run; every llama-NAME-bench.json in it gives one t/s per test (pp512, pp2048,
tg128, ...). For each model and test: the sessions it appears in, the mean, min and max, and the spread, (max - min) /
mean. A cell missing from a session is listed, not dropped. Exit 1 when a cell's spread is over the limit (default 2 %)
or a cell is in fewer than two sessions; 2 on unreadable input.
"""
import json
from pathlib import Path
import sys


def test_name(row):
    p, g, d = row.get("n_prompt", 0), row.get("n_gen", 0), row.get("n_depth", 0)
    name = f"pp{p}" if p and not g else f"tg{g}" if g and not p else f"pp{p}+tg{g}"
    return name + (f"@d{d}" if d else "")


def session(folder):
    cells = {}
    for path in sorted(Path(folder).glob("llama-*-bench.json")):
        model = path.name[len("llama-"):-len("-bench.json")]
        for row in json.loads(path.read_text()):
            cells[(model, test_name(row))] = float(row["avg_ts"])
    return cells


def main(argv):
    limit = 2.0
    if argv[:1] == ["--limit"]:
        limit, argv = float(argv[1]), argv[2:]
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        runs = [session(folder) for folder in argv]
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"bench-spread: {error}", file=sys.stderr)
        return 2
    keys = sorted({key for run in runs for key in run})
    if not keys:
        print("bench-spread: no llama-*-bench.json in " + " ".join(argv), file=sys.stderr)
        return 2
    bad = 0
    print("model\ttest\tsessions\tmean t/s\tmin\tmax\tspread %\tmissing from")
    for key in keys:
        values = [run[key] for run in runs if key in run]
        missing = [folder for folder, run in zip(argv, runs) if key not in run]
        mean = sum(values) / len(values)
        spread = (max(values) - min(values)) / mean * 100 if mean else 0.0
        over = len(values) < 2 or spread > limit
        bad += over
        print(f"{key[0]}\t{key[1]}\t{len(values)}\t{mean:.2f}\t{min(values):.2f}\t{max(values):.2f}\t{spread:.2f}"
              f"{' OVER' if over else ''}\t{' '.join(Path(m).name for m in missing) or '-'}")
    print(f"{len(keys)} cells over {len(runs)} sessions, {bad} over the {limit:g} % limit or in fewer than 2")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
