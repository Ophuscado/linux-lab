#!/usr/bin/env python3
"""ane-bench.py: the Neural Engine as macOS uses it, for the Linux driver (omarchy-ane) to be measured against.

    python ane-bench.py OUT_DIR       (needs coremltools and numpy; collect.sh's 'anebench' step installs them)

Builds small Core ML programs with coremltools' MIL builder, the same kinds omarchy-ane's tests run:
  add20         20 chained fp16 adds on a 1x64x1x64 tensor (its smoke test)
  linear-B-N-K  y = x W^T with W N x K in fp16, batch B: a model's matrix-vector (B=1) and a prompt-like batch
and runs each on every compute-unit choice (CPU only, CPU+GPU, CPU+Neural Engine, all). Prints, per model and
choice, the median time of one prediction and for the linear ones the weight bandwidth. Where Core ML can say
(macOS 14.4+, MLComputePlan), it also records on which device each operation was planned.
Each line starts with a timestamp, so powermetrics' ane_power samples taken meanwhile can be matched to it.
"""
import json
import os
import sys
import time

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import types

OUT = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != "--plan" else "."
# The models (up to 117 MB of weights each) stay out of the results archive.
MODELS = os.environ.get("ANE_MODELS", os.path.expanduser("~/linux-lab-macos/ane-models"))
os.makedirs(OUT, exist_ok=True)
os.makedirs(MODELS, exist_ok=True)
UNITS = [("cpu", ct.ComputeUnit.CPU_ONLY), ("cpu+gpu", ct.ComputeUnit.CPU_AND_GPU),
         ("cpu+ane", ct.ComputeUnit.CPU_AND_NE), ("all", ct.ComputeUnit.ALL)]
TARGET = ct.target.macOS13


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)


def add20():
    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 64, 1, 64), dtype=types.fp32)], opset_version=TARGET)
    def prog(x):
        y = x
        for _ in range(20):
            y = mb.add(x=y, y=x)
        return y
    return prog, {"x": np.random.default_rng(1).standard_normal((1, 64, 1, 64)).astype(np.float32)}, 0


def linear(batch, n, k):
    w = (np.random.default_rng(0).standard_normal((n, k)) * 0.02).astype(np.float32)

    @mb.program(input_specs=[mb.TensorSpec(shape=(batch, k), dtype=types.fp32)], opset_version=TARGET)
    def prog(x):
        return mb.linear(x=x, weight=w)
    return prog, {"x": np.random.default_rng(1).standard_normal((batch, k)).astype(np.float32)}, n * k * 2


def conv(seq, n, k):
    # The layout Apple's own transformer code uses for the Neural Engine (ml-ane-transformers): activations as
    # (1, channels, 1, sequence) and the matrix as a 1x1 convolution. On 28 Oct Core ML planned every batch-1 linear
    # on the CPU and only the batch-64 one on the Neural Engine.
    w = (np.random.default_rng(0).standard_normal((n, k, 1, 1)) * 0.02).astype(np.float32)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, k, 1, seq), dtype=types.fp32)], opset_version=TARGET)
    def prog(x):
        return mb.conv(x=x, weight=w)
    return prog, {"x": np.random.default_rng(1).standard_normal((1, k, 1, seq)).astype(np.float32)}, n * k * 2


def add20_large():
    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 512, 1, 512), dtype=types.fp32)], opset_version=TARGET)
    def prog(x):
        y = x
        for _ in range(20):
            y = mb.add(x=y, y=x)
        return y
    return prog, {"x": np.random.default_rng(1).standard_normal((1, 512, 1, 512)).astype(np.float32)}, 0


def plan(path):
    # In a child process: MLComputePlan aborted the whole run on 28 Oct (a C++ exception on an .mlpackage path).
    import subprocess
    r = subprocess.run([sys.executable, __file__, "--plan", path], capture_output=True, text=True, timeout=300)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return f"unavailable: exit {r.returncode}: {(r.stderr or r.stdout)[-300:]}"


def plan_child(path):
    # Which device Core ML plans each op on (macOS 14.4+ and coremltools 8); absent elsewhere. Needs the compiled model.
    try:
        from coremltools.models.compute_plan import MLComputePlan
        cp = MLComputePlan.load_from_path(path=path, compute_units=ct.ComputeUnit.ALL)
        fn = cp.model_structure.program.functions["main"]
        res = []
        for op in fn.block.operations:
            u = cp.get_compute_device_usage_for_mlprogram_operation(op)
            res.append({"op": op.operator_name,
                        "preferred": type(u.preferred_compute_device).__name__ if u else None,
                        "supported": [type(d).__name__ for d in u.supported_compute_devices] if u else None})
        return res
    except Exception as e:
        return f"unavailable: {type(e).__name__}: {e}"


def main():
    models = {"add20": add20(), "linear-1-4096-4096": linear(1, 4096, 4096), "linear-64-4096-4096": linear(64, 4096, 4096),
              "linear-1-8192-2048": linear(1, 8192, 2048), "linear-1-14336-4096": linear(1, 14336, 4096),
              "add20-512": add20_large(), "conv-1-4096-4096": conv(1, 4096, 4096), "conv-16-4096-4096": conv(16, 4096, 4096),
              "conv-64-4096-4096": conv(64, 4096, 4096), "conv-256-4096-4096": conv(256, 4096, 4096),
              "conv-512-4096-4096": conv(512, 4096, 4096)}
    results = {"macos": os.uname().release, "coremltools": ct.__version__, "runs": []}
    for name, (prog, inputs, wbytes) in models.items():
        path = os.path.join(MODELS, f"{name}.mlpackage")
        m = ct.convert(prog, convert_to="mlprogram", compute_precision=ct.precision.FLOAT16, minimum_deployment_target=TARGET)
        m.save(path)
        compiled = ct.models.utils.compile_model(path)
        results.setdefault("plans", {})[name] = plan(compiled)
        for uname, unit in UNITS:
            try:
                t = time.time()
                mm = ct.models.MLModel(path, compute_units=unit)
                load_s = time.time() - t
                for _ in range(5):
                    mm.predict(inputs)
                times = []
                end = time.time() + 6
                while time.time() < end and len(times) < 2000:
                    t = time.perf_counter()
                    mm.predict(inputs)
                    times.append(time.perf_counter() - t)
                med = float(np.median(times))
                r = {"model": name, "units": uname, "load_s": round(load_s, 3), "runs": len(times),
                     "median_ms": round(med * 1e3, 4), "p10_ms": round(float(np.percentile(times, 10)) * 1e3, 4)}
                if wbytes:
                    r["weight_GBps"] = round(wbytes / med / 1e9, 1)
                log(f"{name} {uname}: {r['median_ms']} ms median over {len(times)}" + (f", {r['weight_GBps']} GB/s of weights" if wbytes else ""))
            except Exception as e:
                r = {"model": name, "units": uname, "error": f"{type(e).__name__}: {e}"}
                log(f"{name} {uname}: {r['error']}")
            results["runs"].append(r)
    with open(os.path.join(OUT, "ane-bench.json"), "w") as f:
        json.dump(results, f, indent=1)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--plan":
        print(json.dumps(plan_child(sys.argv[2])))
    else:
        main()
