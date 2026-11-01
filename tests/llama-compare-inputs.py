#!/usr/bin/env python3
"""Hardware-free step selection checks; no model, driver or GPU is used."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "gpu" / "llama-compare.sh"


class StepSelection(unittest.TestCase):
    def invoke(self, root, steps):
        env = dict(os.environ, STEPS=steps, LLAMA_BIN=str(root / "bin"),
                   LLM=str(root / "no-models"), MESA_SIDE=str(root / "no-mesa"),
                   GPU_LOCK=str(root / "lock"), COMPARE_OUT=str(root / "out"))
        return subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True, timeout=10)

    def test_invalid_selections_fail_before_side_effects(self):
        for steps in ("typo", "bench typo", " \t\n ", "bench,ops", "*", "bench\nunknown"):
            with self.subTest(steps=steps), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                result = self.invoke(root, steps)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertRegex(result.stderr, "unknown benchmark step|no benchmark steps")
                self.assertFalse((root / "out").exists())
                self.assertFalse((root / "lock").exists())

    def test_whitespace_selection_requires_selected_binary(self):
        for steps in ("bench", "\tbench\n", "bench\tbench", "\nbench\nbench\n"):
            with self.subTest(steps=steps), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                result = self.invoke(root, steps)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("no llama-bench", result.stderr)
                self.assertFalse((root / "out").exists())
                self.assertFalse((root / "lock").exists())

    def test_valid_whitespace_selection_keeps_dependency_scope(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "bin").mkdir()
            backend = root / "bin/test-backend-ops"
            backend.write_text("#!/bin/sh\nexit 0\n")
            backend.chmod(0o755)
            result = self.invoke(root, "\n\tops\t ops\n")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            provenance = next((root / "out").glob("compare-*/provenance.json"))
            self.assertEqual(json.loads(provenance.read_text())["steps"], ["ops"])


if __name__ == "__main__":
    unittest.main()
