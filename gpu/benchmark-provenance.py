#!/usr/bin/env python3
"""Identify measured artifacts without probing the GPU or recording the full environment."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys

FLAGS = (
    "AGX_CLUSTER_OFF", "AGX_BIT47", "AGX_NO_ILP_SCHED", "AGX_GLOBAL_WAITS", "AGX_HOIST_LOADS",
    "HK_PERFTEST", "HK_CDM_DEFER_FLUSH", "ROWS", "THREADS",
    "GGML_VK_WT_M", "GGML_VK_WT_S", "GGML_VK_MMID_SIZES", "GGML_VK_MMID_S_MAX",
    "GGML_VK_MMV_ID_MAX", "GGML_VK_MMV_ID_PER_EXPERT", "GGML_VK_MMV_MAX_COLS",
    "GGML_VK_DMMV_WG", "GGML_VK_MMV_SIMD", "GGML_VK_SHADER_CORES",
    "GGML_VK_RM_STDQ", "GGML_VK_RM_KQ", "GGML_VK_RM_F16", "GGML_VK_DMMV_LARGE",
)


def artifact(path):
    info = {"name": path.name, "sha256": None}
    try:
        details = path.stat()
        if not stat.S_ISREG(details.st_mode) or details.st_size > 512 * 1024 * 1024:
            return dict(info, status="not_a_bounded_regular_file")
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return dict(info, sha256=digest.hexdigest(), bytes=details.st_size, status="ok")
    except OSError:
        return dict(info, status="unavailable")


def checkout(path, untracked="normal"):
    # An observed checkout revision is not a claim about which source built a binary.
    try:
        head = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=2,
        )
        if head.returncode:
            return {"head": None, "dirty": None}
        dirty = subprocess.run(
            ["git", "-C", str(path), "status", "--porcelain", "--untracked-files=" + untracked],
            capture_output=True, text=True, timeout=2,
        )
        return {"head": head.stdout.strip(), "dirty": bool(dirty.stdout) if not dirty.returncode else None}
    except (OSError, subprocess.TimeoutExpired):
        return {"head": None, "dirty": None}


def driver_manifest(path):
    try:
        if not stat.S_ISREG(path.stat().st_mode) or path.stat().st_size > 1024 * 1024:
            raise ValueError("not a bounded manifest")
        entry = {"manifest": artifact(path)}
        # gpu/mesa-side.sh installs PREFIX/share/vulkan/icd.d/*.json and keeps the tree it built beside PREFIX as
        # src-NAME, with .lab-state naming the pinned commit and the series applied: observed, as checkout() says.
        prefix = path.parent.parent.parent.parent
        source = prefix.parent / ("src-" + prefix.name)
        if (source / ".git").exists():
            try:
                state = (source / ".lab-state").read_text().strip() or None
            except OSError:
                state = None
            # Tracked files only: mesa-side writes .lab-state and build.log into the tree itself.
            entry["observed_source"] = dict(checkout(source, untracked="no"), path=source.name, lab_state=state)
        library = json.loads(path.read_text())["ICD"]["library_path"]
        if not isinstance(library, str) or not library:
            raise ValueError("invalid library path")
        if not Path(library).is_absolute() and "/" not in library:
            entry["library"] = {"name": library, "sha256": None, "status": "system_search_unresolved"}
        else:
            target = Path(library)
            entry["library"] = artifact(target if target.is_absolute() else path.parent / target)
        return entry
    except (OSError, ValueError, KeyError, TypeError):
        return {"manifest": {"name": path.name, "sha256": None, "status": "invalid_or_unavailable"}}


def capture(lab, binaries, wait_seconds, environment=None):
    env = os.environ if environment is None else environment
    series = lab / "src-patches/llama.cpp/honeykrisp"
    base = None
    try:
        base = next(line.split("=", 1)[1].split("#", 1)[0].strip()
                    for line in (series / "BASE").read_text().splitlines() if line.startswith("BASE="))
    except (OSError, StopIteration):
        pass
    manifests = env.get("VK_DRIVER_FILES") or env.get("VK_ICD_FILENAMES")
    return {
        "schema": 1,
        "steps": [step for step in ("mmv", "mmid", "pp", "ops", "bench", "batches", "depth", "perf", "sync", "spec")
                  if step in (env.get("STEPS") or "").split()],
        "lock_wait_seconds": wait_seconds,
        "lock_wait_resolution_seconds": 1,
        "observed_checkouts": {"lab": checkout(lab), "nearest_binary_checkout": checkout(binaries)},
        "script": artifact(lab / "gpu/llama-compare.sh"),
        "series_base": base,
        "series_patches": [artifact(path) for path in sorted(series.glob("*.patch"))],
        "executables": [artifact(binaries / name) for name in
                        ("llama-bench", "llama-server", "test-backend-ops") if (binaries / name).is_file()],
        "backend_libraries": [artifact(binaries / name) for name in
                             ("libllama.so", "libggml-vulkan.so", "libggml-cpu.so") if (binaries / name).is_file()],
        "tuning": {key: env.get(key) for key in FLAGS},
        "driver_selection": {
            "mode": "explicit_manifest_candidates" if manifests else "system_default_unresolved",
            "manifests": [driver_manifest(Path(path)) for path in manifests.split(os.pathsep) if path] if manifests else [],
        },
    }


if __name__ == "__main__":
    lab, binaries, output, wait = sys.argv[1:]
    target = Path(output)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_text(json.dumps(capture(Path(lab), Path(binaries), int(wait)), indent=2) + "\n")
    temporary.replace(target)
