#!/usr/bin/env python3
"""results-ingest.py: the macOS runs of collect.sh, out of whatever zips and folders they were gathered into, into
one tree that can be published.

    python3 -I macos/results-ingest.py SOURCE... OUT

SOURCE: zip files and folders, in any mix (copies of ~/linux-lab-macos with venvs, llama.cpp checkouts, model
copies and duplicate runs are fine: only runs are taken). OUT: the tree to write, OUT/macos-<major>/<run>/...

What is a run: a folder or a .tar.gz named YYYYMMDD-HHMMSS, as collect.sh writes them; loose result files beside
them (ane-fw-sha256-*.txt, apciec.txt, tbt-pci-devices.txt) go to OUT/macos-<major>/extra/. The macOS major
version comes from the run's own hw-sysctl.txt (sw_vers), else from a 13/14/15 at the start of the source's name,
else from INGEST_DEFAULT, else it is 'unknown'.

Left out: every run's private/ (Apple's compiled GPU and Neural Engine code, Metal's shader cache: for study, not
for publishing), Core ML model copies (*.mlpackage, weight.bin), __MACOSX and .DS_Store. Text, including text
inside .gz, is scrubbed: the home folder becomes ~, the host name <host>, UUIDs <uuid>, MAC addresses <mac>; lines
naming a serial number or anything credential-like are dropped (SERIAL). The same run found in several sources is merged file by file; two different
copies of one file are both kept (the second as NAME.alt-N) and listed in OUT/INGEST.txt with everything else done.
"""
import gzip
import hashlib
import io
import os
import re
import sys
import tarfile
import zipfile

RUN = re.compile(r"(?:^|/)(\d{8}-\d{6})(?:\.tar\.gz)?(?:/|$)")
EXTRA = re.compile(r"(?:^|/)(ane-fw-sha256-\d+\.txt|apciec\.txt|tbt-pci-devices\.txt)$")
SKIP = re.compile(r"(^|/)(__MACOSX|private|venv|llama\.cpp|ane-models)(/|$)|\.DS_Store$|\.mlpackage(/|$)|weight\.bin$|(^|/)\._")
# INGEST_PRIVATE=1: the opposite selection, only each run's private/ (Apple's compiled code, kept locally, never
# published), without the Core ML model copies; nothing is scrubbed.
PRIVATE = os.environ.get("INGEST_PRIVATE") == "1"
if PRIVATE:
    SKIP = re.compile(r"(^|/)(__MACOSX|venv|llama\.cpp|ane-models)(/|$)|\.DS_Store$|\.mlpackage(/|$)|weight\.bin$|(^|/)\._")
TEXT = {".txt", ".json", ".tsv", ".log", ".csv", ".md", ".xml"}
UUID = re.compile(rb"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b")
MAC = re.compile(rb"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b")
# Lines dropped whole: serial numbers (the owner of these runs publishes device identifiers otherwise, 29 Oct) and
# anything that could be a credential. UUIDs are replaced, not dropped, so paths through Preboot volumes stay.
SERIAL = re.compile(rb"serial|region-info|mobileme-token|auth-?token", re.I)

log = []


def scrub(data, home, host):
    out = []
    for line in data.splitlines(keepends=True):
        if SERIAL.search(line):
            continue
        if home:
            line = line.replace(home, b"~")
        if host:
            line = line.replace(host, b"<host>")
        line = UUID.sub(b"<uuid>", line)
        line = MAC.sub(b"<mac>", line)
        out.append(line)
    return b"".join(out)


def clean(name, data, home, host):
    if PRIVATE:
        return data
    if os.path.splitext(name)[1] in (".tsv",) or name.endswith(".tsv.gz"):
        # input-log: raw reports and events, no names; scrubbing would cut them by their hex.
        return data
    base = name.rsplit("/", 1)[-1]
    if base.endswith(".gz") and not base.endswith(".tar.gz"):
        inner = os.path.splitext(base[:-3])[1]
        if inner in TEXT:
            try:
                return gzip.compress(scrub(gzip.decompress(data), home, host), mtime=0)
            except OSError:
                return data
        return data
    if os.path.splitext(base)[1] in TEXT:
        return scrub(data, home, host)
    return data


def entries(src):
    """(path inside the source, bytes) for every file of a zip or folder, nested run .tar.gz unpacked."""
    def from_tar(prefix, blob):
        with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as t:
            for m in t.getmembers():
                if m.isfile():
                    yield prefix + "/" + m.name.lstrip("./"), t.extractfile(m).read()

    def walk():
        if zipfile.is_zipfile(src):
            with zipfile.ZipFile(src) as z:
                for i in z.infolist():
                    if not i.is_dir():
                        yield i.filename, (lambda i=i: z.read(i))
        else:
            for root, _, files in os.walk(src):
                for f in files:
                    p = os.path.join(root, f)
                    yield os.path.relpath(p, src), (lambda p=p: open(p, "rb").read())

    for name, read in walk():
        if SKIP.search(name):
            continue
        base = name.rsplit("/", 1)[-1]
        if re.fullmatch(r"\d{8}-\d{6}\.tar\.gz", base):
            for n, b in from_tar(name.rsplit("/", 1)[0], read()):
                if not SKIP.search(n) and (not PRIVATE or "/private/" in n):
                    yield n, b
        elif PRIVATE:
            if RUN.search(name) and "/private/" in name:
                yield name, read()
        elif RUN.search(name) or EXTRA.search(name):
            yield name, read()


def major_hint(src):
    m = re.match(r"(1[3-9]|2\d)\b", os.path.basename(src))
    return m.group(1) if m else None


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    *sources, out = argv
    home = os.environ.get("INGEST_HOME", "/Users/" + os.environ.get("INGEST_USER", os.environ.get("USER", ""))).encode()
    host = os.environ.get("INGEST_HOST", "").encode() or None
    runs = {}     # run id -> {relative path: [(sha, bytes, source)]}
    extras = {}   # (hint, name) -> [(sha, bytes, source)]
    for src in sources:
        hint = major_hint(src) or os.environ.get("INGEST_DEFAULT")
        n = 0
        for name, data in entries(src):
            m = RUN.search(name)
            if m:
                rel = name[m.end():] if name[m.end() - 1] == "/" else ""
                if not rel:
                    continue
                runs.setdefault(m.group(1), {}).setdefault(rel, [])
                lst = runs[m.group(1)][rel]
                sha = hashlib.sha256(data).hexdigest()
                if all(s != sha for s, _, _ in lst):
                    lst.append((sha, data, src))
                runs[m.group(1)].setdefault("\0hint", hint)
            else:
                e = EXTRA.search(name).group(1)
                lst = extras.setdefault((hint, e), [])
                sha = hashlib.sha256(data).hexdigest()
                if all(s != sha for s, _, _ in lst):
                    lst.append((sha, data, src))
            n += 1
        log.append(f"{os.path.basename(src.rstrip('/'))}: {n} run files taken")
    total = 0
    for run, files in sorted(runs.items()):
        hint = files.pop("\0hint", None)
        major = hint or "unknown"
        sysctl = files.get("hw-sysctl.txt")
        if sysctl:
            m = re.search(rb"ProductVersion:\s*(\d+)", sysctl[0][1])
            if m:
                major = m.group(1).decode()
        d = os.path.join(out, f"macos-{major}", run)
        for rel, copies in sorted(files.items()):
            for i, (sha, data, src) in enumerate(copies):
                p = os.path.join(d, rel if i == 0 else f"{rel}.alt-{i}")
                os.makedirs(os.path.dirname(p), exist_ok=True)
                b = clean(rel, data, home, host)
                open(p, "wb").write(b)
                total += len(b)
                if i:
                    log.append(f"{run}/{rel}: a different copy from {os.path.basename(src.rstrip('/'))} kept as .alt-{i}")
        log.append(f"{run}: macOS {major}, {len(files)} files")
    for (hint, e), copies in sorted(extras.items(), key=lambda x: (x[0][0] or "", x[0][1])):
        for i, (sha, data, src) in enumerate(copies):
            p = os.path.join(out, f"macos-{hint or 'unknown'}", "extra", e if i == 0 else f"{e}.alt-{i}")
            os.makedirs(os.path.dirname(p), exist_ok=True)
            b = clean(e, data, home, host)
            open(p, "wb").write(b)
            total += len(b)
    log.append(f"total {total / 1e6:.1f} MB")
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "INGEST.txt"), "w").write("\n".join(log) + "\n")
    print("\n".join(log[-40:]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
