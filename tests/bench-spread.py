#!/usr/bin/env python3
"""bench-spread.py: the spread per model and test, missing cells listed, the exit status by the limit."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "gpu/bench-spread.py"


def row(p, g, ts, d=0):
    return {"n_prompt": p, "n_gen": g, "n_depth": d, "avg_ts": ts}


class Spread(unittest.TestCase):
    def run_on(self, sessions, *extra):
        with tempfile.TemporaryDirectory() as folder:
            dirs = []
            for i, models in enumerate(sessions):
                d = Path(folder) / f"compare-{i}"
                d.mkdir()
                for model, rows in models.items():
                    (d / f"llama-{model}-bench.json").write_text(json.dumps(rows))
                dirs.append(str(d))
            return subprocess.run([sys.executable, "-I", str(SCRIPT), *extra, *dirs], capture_output=True, text=True)

    def test_within_limit(self):
        r = self.run_on([{"llama2": [row(512, 0, 100.0), row(0, 128, 50.0)]},
                         {"llama2": [row(512, 0, 101.0), row(0, 128, 50.5)]},
                         {"llama2": [row(512, 0, 100.5), row(0, 128, 50.0)]}])
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("llama2\tpp512\t3\t100.50\t100.00\t101.00\t1.00\t-", r.stdout)
        self.assertIn("llama2\ttg128\t3\t", r.stdout)

    def test_over_limit_and_missing(self):
        r = self.run_on([{"qwen": [row(512, 0, 100.0)], "gemma": [row(0, 128, 40.0)]},
                         {"qwen": [row(512, 0, 110.0)]}])
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("qwen\tpp512\t2\t105.00\t100.00\t110.00\t9.52 OVER\t-", r.stdout)
        self.assertIn("gemma\ttg128\t1\t40.00\t40.00\t40.00\t0.00 OVER\tcompare-1", r.stdout)

    def test_limit_flag(self):
        r = self.run_on([{"qwen": [row(512, 0, 100.0)]}, {"qwen": [row(512, 0, 110.0)]}], "--limit", "10")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_depth_named(self):
        r = self.run_on([{"m": [row(0, 32, 30.0, d=4096)]}, {"m": [row(0, 32, 30.0, d=4096)]}])
        self.assertIn("m\ttg32@d4096\t2\t", r.stdout)

    def test_unreadable_and_empty(self):
        self.assertEqual(self.run_on([{"x": "not a list"}]).returncode, 2)
        self.assertEqual(self.run_on([{}]).returncode, 2)


if __name__ == "__main__":
    unittest.main()
