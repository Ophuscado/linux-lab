#!/usr/bin/env python3
"""Hardware-free confinement and shared-lock regression for llama-bench.sh."""
import fcntl
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "gpu" / "llama-bench.sh"


class ConfinedBench(unittest.TestCase):
    def test_shared_lock_and_output_override(self):
        for readonly, fail_call in ((False, 0), (True, 0), (True, 1), (True, 2), (True, 3), (True, 4), (True, 5)):
            with self.subTest(readonly=readonly, fail_call=fail_call), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                source = root / "source"
                (source / ".git").mkdir(parents=True)
                commands = root / "commands"
                commands.mkdir()
                calls = root / "calls"
                def executable(path, text):
                    path.write_text("#!/bin/sh\n" + text)
                    path.chmod(0o755)
                for name in ("rpm", "cmake", "lsmod"):
                    executable(commands / name, "exit 0\n")
                executable(commands / "git", "echo fixture-revision\n")
                executable(commands / "vulkaninfo", "echo deviceName=fixture\n")
                for variant in ("build-cpu", "build-gpu"):
                    directory = source / variant / "bin"
                    directory.mkdir(parents=True)
                    executable(directory / "llama-bench",
                               'echo call >> "$BENCH_CALLS"\nn=$(wc -l < "$BENCH_CALLS")\n'
                               'if [ "$n" -eq "$BENCH_FAIL_CALL" ]; then echo raw-failure-sentinel; exit 7; fi\n'
                               'echo "| fixture |"\necho "Total time 1 us"\n')
                model = root / "model.gguf"
                model.touch()
                lock = root / "gpu.lock"
                lock.write_text("keep existing lock contents\n")
                output = root / "result.txt"
                env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                           LLAMA_SRC=str(source), LLAMA_REF="", THREADS="1",
                           GPU_LOCK=str(lock), BENCH_OUT=str(output), BENCH_CALLS=str(calls), BENCH_FAIL_CALL=str(fail_call),
                           TMPDIR=str(root))
                with lock.open("r") as holder:
                    fcntl.flock(holder, fcntl.LOCK_EX)
                    if readonly:
                        lock.chmod(0o444)
                    process = subprocess.Popen(["bash", str(SCRIPT), str(model)], env=env,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    try:
                        deadline = time.monotonic() + 5
                        while not (source / "build-gpu.log").exists() and process.poll() is None:
                            self.assertLess(time.monotonic(), deadline, "fixture build did not finish")
                            time.sleep(0.02)
                        # Let it reach flock after the fake build, while the parent owns the lock.
                        time.sleep(0.15)
                        self.assertIsNone(process.poll(), "runner exited instead of waiting on the shared lock")
                        self.assertFalse(calls.exists(), "benchmark ran without acquiring the shared lock")
                        self.assertFalse(output.exists())
                        fcntl.flock(holder, fcntl.LOCK_UN)
                        stdout, stderr = process.communicate(timeout=10)
                        self.assertEqual(process.returncode, 1 if fail_call else 0, stdout + stderr)
                        self.assertEqual(calls.read_text().splitlines(), ["call"] * 5)
                        self.assertIn("===== cpu", output.read_text())
                        if fail_call:
                            logs = re.findall(r"raw log: (.+)", output.read_text())
                            self.assertEqual(len(logs), 1, stdout + stderr)
                            self.assertIn("rc 7", output.read_text())
                            self.assertIn("raw-failure-sentinel", Path(logs[0]).read_text())
                        else:
                            self.assertNotIn("raw log:", output.read_text())
                        self.assertEqual(lock.read_text(), "keep existing lock contents\n")
                    finally:
                        if process.poll() is None:
                            process.kill()
                        process.communicate()
                        lock.chmod(0o644)


if __name__ == "__main__":
    unittest.main()
