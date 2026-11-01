#!/usr/bin/env python3
"""Exercise llama-compare's server lifecycle without a GPU or model service."""
import fcntl
import os
from pathlib import Path
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]


class SpecLifecycle(unittest.TestCase):
    def run_case(self, mode):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("gpu", "macos", "models", "bin"):
                (root / name).mkdir()
            listener = socket.socket()
            self.addCleanup(listener.close)
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
            if mode == "port-busy":
                listener.listen()
            else:
                listener.close()
            script = root / "gpu/llama-compare.sh"
            script.write_text((REPO / "gpu/llama-compare.sh").read_text().replace("8099", str(port)))
            (root / "gpu/llama-run.sh").touch()
            (root / "macos/spec-req.py").touch()
            (root / "macos/models.txt").write_text("test|model.gguf|\n")
            (root / "models/model.gguf").touch()

            def executable(name, text):
                path = root / "bin" / name
                path.write_text(text)
                path.chmod(0o755)

            executable("llama-server", f"""#!{sys.executable}
import os
import time
if os.environ["MODE"] == "early-exit":
    raise SystemExit(7)
with open(os.environ["PIDS"], "a") as output:
    output.write(str(os.getpid()) + "\\n")
while True:
    time.sleep(.02)
""")
            executable("python3", f"""#!/bin/sh
if [ "$2" = -c ]; then exec {shlex.quote(sys.executable)} "$@"; fi
echo request >> "$REQUESTS"
echo "gen fake"
if [ "$MODE" = request-fail ]; then exit 9; fi
""")
            executable("curl", """#!/bin/sh
case "$MODE" in
    not-ready|signal|early-exit) exit 1 ;;
    *) /bin/sleep .02; exit 0 ;;
esac
""")
            executable("sleep", "#!/bin/sh\n/bin/sleep .001\n")
            env = dict(
                os.environ,
                STEPS="spec",
                LLAMA_BIN=str(root / "bin"),
                GPU_LOCK=str(root / "gpu.lock"),
                COMPARE_OUT=str(root / "out"),
                MESA_SIDE=str(root / "mesa"),
                LLM=str(root / "models"),
                PATH=str(root / "bin") + ":" + os.environ["PATH"],
                MODE=mode,
                PIDS=str(root / "pids"),
                REQUESTS=str(root / "requests"),
            )
            process = subprocess.Popen(
                ["bash", str(script)],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=True,
            )
            try:
                if mode == "signal":
                    deadline = time.monotonic() + 3
                    while not (root / "pids").exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue((root / "pids").exists(), "server never started")
                    process.send_signal(signal.SIGTERM)
                output, _ = process.communicate(timeout=120)
                if mode == "success":
                    self.assertEqual(process.returncode, 0, output)
                else:
                    self.assertNotEqual(process.returncode, 0, output)
                self.assertEqual((root / "requests").exists(), mode in ("request-fail", "success"), output)
                if mode not in ("signal", "success"):
                    self.assertTrue(list((root / "out").glob("compare-*/failed.txt")), output)
                if (root / "pids").exists():
                    for pid in map(int, (root / "pids").read_text().splitlines()):
                        with self.assertRaises(ProcessLookupError, msg=f"server leaked: {pid}"):
                            os.kill(pid, 0)
                with open(root / "gpu.lock", "a") as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                if process.poll() is None:
                    process.communicate()
                listener.close()

    def test_request_failure(self):
        self.run_case("request-fail")

    def test_early_exit(self):
        self.run_case("early-exit")

    def test_readiness_timeout(self):
        self.run_case("not-ready")

    def test_termination(self):
        self.run_case("signal")

    def test_occupied_port(self):
        self.run_case("port-busy")

    def test_success(self):
        self.run_case("success")


class PerfSweeps(unittest.TestCase):
    def run_case(self, mode):
        for family in ("mmv", "mmid"):
            with self.subTest(family=family), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / "bin").mkdir()
                backend = root / "bin/test-backend-ops"
                backend.write_text("""#!/bin/sh
case "$MODE" in
    empty) exit 0 ;;
    unmatched) echo "not a timing"; exit 0 ;;
    failed) echo "backend failed" >&2; exit 7 ;;
    partial)
        if [ "$FAMILY" = mmv ] && [ "$GGML_VK_RM_F16" = 2 ]; then exit 0; fi
        if [ "$FAMILY" = mmid ] && [ "$GGML_VK_MMID_SIZES" = s ]; then exit 0; fi ;;
esac
if [ "$FAMILY" = mmv ]; then
    echo "MUL_MAT(type_a=f16,example 1.0 us/run)"
else
    echo "MUL_MAT_ID(type_a=q8_0,type_b=f32,n_mats=32,n_used=4,b=0,m=4096,n=32,k=14336,m_v=0) 12.5 us/run"
fi
""")
                backend.chmod(0o755)
                env = dict(
                    os.environ,
                    STEPS=family,
                    FAMILY=family,
                    MODE=mode,
                    LLAMA_BIN=str(root / "bin"),
                    GPU_LOCK=str(root / "gpu.lock"),
                    COMPARE_OUT=str(root / "out"),
                    MESA_SIDE=str(root / "mesa"),
                    LLM=str(root / "models"),
                    MMV_SWEEP="1,large,4,4,1 1,large,4,4,2" if mode == "partial" else "1,large,4,4,1",
                    MMID_SWEEP="m s" if mode == "partial" else "m",
                )
                result = subprocess.run(
                    ["bash", str(REPO / "gpu/llama-compare.sh")],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
                )
                out = next((root / "out").glob("compare-*"))
                rows = (out / f"{family}.txt").read_text().splitlines()
                self.assertEqual(len(rows), 1 if mode in ("valid", "partial") else 0, result.stdout)
                self.assertTrue(list(out.glob(f"{family}-*.log")), result.stdout)
                if mode == "valid":
                    self.assertEqual(result.returncode, 0, result.stdout)
                else:
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertTrue((out / "failed.txt").exists(), result.stdout)

    def test_empty_output(self):
        self.run_case("empty")

    def test_unmatched_output(self):
        self.run_case("unmatched")

    def test_backend_failure(self):
        self.run_case("failed")

    def test_valid_timings(self):
        self.run_case("valid")

    def test_later_empty_point(self):
        self.run_case("partial")


if __name__ == "__main__":
    unittest.main()
