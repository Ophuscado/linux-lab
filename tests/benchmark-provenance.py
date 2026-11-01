#!/usr/bin/env python3
"""Keep provenance tied to artifacts and avoid guessed driver identities or secret environment data."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "gpu/benchmark-provenance.py"
spec = importlib.util.spec_from_file_location("benchmark_provenance", MODULE)
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


class Provenance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lab = self.root / "lab"
        self.binaries = self.root / "bin"
        self.binaries.mkdir()
        (self.lab / "gpu").mkdir(parents=True)
        (self.lab / "gpu/llama-compare.sh").write_text("script\n")
        self.series = self.lab / "src-patches/llama.cpp/honeykrisp"
        self.series.mkdir(parents=True)
        (self.series / "BASE").write_text("BASE=abc123 # pinned source\n")
        (self.series / "0001.patch").write_text("patch\n")
        (self.binaries / "test-backend-ops").write_bytes(b"binary-one")
        self.manifest = self.root / "driver.json"
        self.library = self.root / "driver.so"
        self.library.write_bytes(b"driver-one")

    def configured(self, library):
        self.manifest.write_text(json.dumps({"ICD": {"library_path": library}}))
        return provenance.capture(self.lab, self.binaries, 7, {"VK_DRIVER_FILES": str(self.manifest)})

    def test_relative_driver_and_binary_fingerprints(self):
        data = self.configured("./driver.so")
        self.assertEqual(data["lock_wait_seconds"], 7)
        self.assertEqual(data["series_base"], "abc123")
        self.assertEqual(data["executables"][0]["sha256"], hashlib.sha256(b"binary-one").hexdigest())
        self.assertEqual(data["driver_selection"]["manifests"][0]["library"]["sha256"],
                         hashlib.sha256(b"driver-one").hexdigest())
        self.assertEqual(len(data["series_patches"]), 1)
        (self.binaries / "test-backend-ops").write_bytes(b"binary-two")
        changed = self.configured("./driver.so")
        self.assertNotEqual(data["executables"][0]["sha256"], changed["executables"][0]["sha256"])

    def test_absolute_driver(self):
        data = self.configured(str(self.library))
        self.assertEqual(data["driver_selection"]["manifests"][0]["library"]["status"], "ok")

    def test_bare_library_is_not_guessed_from_manifest_directory(self):
        data = self.configured("driver.so")
        library = data["driver_selection"]["manifests"][0]["library"]
        self.assertIsNone(library["sha256"])
        self.assertEqual(library["status"], "system_search_unresolved")

    def test_unknown_default_and_secrets_excluded(self):
        data = provenance.capture(self.lab, self.binaries, 0, {
            "STEPS": "mmv credential-sentinel", "AGX_CLUSTER_OFF": "1", "AGX_SECRET_TOKEN": "credential-sentinel", "API_KEY": "another-sentinel",
        })
        self.assertEqual(data["driver_selection"]["mode"], "system_default_unresolved")
        self.assertEqual(data["tuning"]["AGX_CLUSTER_OFF"], "1")
        self.assertEqual(data["steps"], ["mmv"])
        encoded = json.dumps(data)
        self.assertNotIn("credential-sentinel", encoded)
        self.assertNotIn("another-sentinel", encoded)
        self.assertNotIn("AGX_SECRET_TOKEN", encoded)

    def test_invalid_manifest(self):
        self.manifest.write_text("not JSON")
        data = provenance.driver_manifest(self.manifest)
        self.assertEqual(data["manifest"]["status"], "invalid_or_unavailable")

    def test_runner_records_default_step_selection(self):
        for name in ("llama-bench", "llama-server", "test-backend-ops"):
            path = self.binaries / name
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
        env = dict(os.environ, LLAMA_BIN=str(self.binaries), MESA_SIDE=str(self.root / "mesa"),
                   LLM=str(self.root / "no-models"), GPU_LOCK=str(self.root / "lock"),
                   COMPARE_OUT=str(self.root / "out"))
        env.pop("STEPS", None)
        result = subprocess.run(
            ["bash", str(MODULE.parent / "llama-compare.sh")], env=env,
            capture_output=True, text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = next((self.root / "out").glob("compare-*/provenance.json"))
        self.assertEqual(json.loads(output.read_text())["steps"], ["ops", "bench", "batches", "depth", "spec"])

    def test_untracked_source_marks_observed_checkout_dirty(self):
        subprocess.run(["git", "init", "-q", str(self.lab)], check=True, capture_output=True)
        subprocess.run([
            "git", "-C", str(self.lab), "-c", "user.name=Fixture",
            "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "-q", "--allow-empty", "-m", "fixture",
        ], check=True, capture_output=True)
        state = provenance.checkout(self.lab)
        self.assertIsNotNone(state["head"])
        self.assertTrue(state["dirty"])

    def test_large_artifact_is_not_read(self):
        path = self.root / "large"
        with path.open("wb") as stream:
            stream.truncate(512 * 1024 * 1024 + 1)
        self.assertEqual(provenance.artifact(path)["status"], "not_a_bounded_regular_file")


if __name__ == "__main__":
    unittest.main()
