#!/bin/bash
# Oracle for gale-ledge. This does the REAL work: fixes the three source bugs,
# writes the reproducible driver /app/solve.py, editable-installs the package,
# and RUNS the driver to produce /app/colib.log and /app/answer.json.
# It never reads /tests.
set -eu

PROJ=/app/proj

# --- 1. Fix the garbage-collector sweep (heap.py): the buggy sweep under-counts
# the final free cell of a run that reaches the end of the arena. ---
python3 - <<'PY'
import re
p = "/app/proj/src/gale/heap.py"
src = open(p).read()
old = """                while i + 1 < n and cells[i] == 0:
                    i += 1
                length = i - begin
                if length > 0:
                    runs.append([begin, length])
                i += 1"""
new = """                while i < n and cells[i] == 0:
                    i += 1
                if i - begin > 0:
                    runs.append([begin, i - begin])"""
assert old in src, "heap pattern not found"
open(p, "w").write(src.replace(old, new))
PY

# --- 2. Fix model composition order (kinetic.py): fold left-to-right. ---
python3 - <<'PY'
p = "/app/proj/src/gale/kinetic.py"
src = open(p).read()
old = "        acc = matmul(m, acc)  # NOTE: application order folded here"
new = "        acc = matmul(acc, m)  # left-to-right application order"
assert old in src, "kinetic pattern not found"
open(p, "w").write(src.replace(old, new))
PY

# --- 3. Implement the async slurp_tree (io.py). ---
python3 - <<'PY'
p = "/app/proj/src/gale/io.py"
src = open(p).read()
old = '''async def slurp_tree(root):
    """Return ``{relative_path: text}`` for every regular file under ``root``."""
    raise NotImplementedError("slurp_tree is not implemented yet")'''
new = '''async def slurp_tree(root):
    """Return ``{relative_path: text}`` for every regular file under ``root``."""
    out = {}
    for dirpath, _dirs, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, encoding="utf-8") as fh:
                out[rel] = fh.read()
    return out'''
assert old in src, "io pattern not found"
open(p, "w").write(src.replace(old, new))
PY

# --- 4. Write the reproducible driver deliverable. ---
cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""gale-ledge reproducibility driver.

Default run (no args): drives the shipped project at /app/proj through every
gate, writes the col suite log to /app/colib.log and the JSON report to
/app/answer.json.

Status mode (used on fresh/malformed fixtures that are mounted read-only):
    python3 solve.py status --manifest M --src S
prints a JSON compliance/size report and never crashes.
"""
import importlib.metadata
import json
import os
import re
import subprocess
import sys


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def _as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def _version_ge(have, need):
    hv = [_as_int(p) for p in have.split(".")]
    nv = [_as_int(p) for p in need.split(".")]
    while len(hv) < len(nv):
        hv.append(0)
    while len(nv) < len(hv):
        nv.append(0)
    return hv >= nv


def dependency_problems(manifest):
    problems = []
    for dep, minv in sorted((manifest.get("dependencies") or {}).items()):
        try:
            have = importlib.metadata.version(dep)
        except Exception:
            problems.append("%s not installed (need >= %s)" % (dep, minv))
            continue
        if not _version_ge(have, minv):
            problems.append("%s version %s < required %s" % (dep, have, minv))
    return problems


def size_problems(src, cap):
    if cap is None or not os.path.isdir(src):
        return []
    problems = []
    for dirpath, _dirs, files in os.walk(src):
        for fn in files:
            full = os.path.join(dirpath, fn)
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            if size > cap:
                problems.append("%s is %db > cap %db" % (full, size, cap))
    return problems


def count_passed(log):
    n = None
    try:
        text = open(log).read()
    except OSError:
        return None
    for line in text.splitlines():
        m = re.search(r"(\d+) passed", line)
        if m:
            n = int(m.group(1))
    return n


def status_mode(args):
    manifest = src = None
    it = iter(args[1:])
    for tok in it:
        if tok == "--manifest":
            manifest = next(it, None)
        elif tok == "--src":
            src = next(it, None)
    problems = []
    manifest_ok = False
    size_cap_ok = True
    if manifest and os.path.exists(manifest):
        try:
            with open(manifest) as fh:
                data = json.load(fh)
            data_problems = dependency_problems(data)
            cap = data.get("source_cap_bytes")
            size_probs = size_problems(src, cap) if src else []
            problems = data_problems + size_probs
            manifest_ok = (not data_problems)
            size_cap_ok = (len(size_probs) == 0)
        except Exception as exc:  # noqa: BLE001 - malformed manifest
            problems = ["malformed manifest: %s" % exc]
    else:
        problems = ["manifest not found"]
    print(json.dumps(
        {"manifest_ok": bool(manifest_ok),
         "size_cap_ok": bool(size_cap_ok),
         "violations": problems}, indent=2))
    return 0


def main():
    args = sys.argv[1:]
    if args and args[0] == "status":
        return status_mode(args)

    root = "/app/proj"
    out = "/app"

    # 1. editable reinstall so gale is installed with the fixed sources.
    r = _run(["python", "-m", "pip", "install", "--no-build-isolation",
              "--no-cache-dir", "-e", root])
    install_ok = r.returncode == 0

    # 2. targeted col suite -> /app/colib.log with a confirmed pass count.
    colib_log = os.path.join(out, "colib.log")
    r = _run(["python", "-m", "pytest", "-q", os.path.join(root, "tests", "col")])
    with open(colib_log, "w") as fh:
        fh.write(r.stdout)
        fh.write("\n" + r.stderr)
    col_ok = r.returncode == 0
    col_passed = count_passed(colib_log)

    # 3. sync bug-fix suites + async fsx (from the installed package).
    r2 = _run(["python", "-m", "pytest", "-q",
               os.path.join(root, "tests", "test_heap.py"),
               os.path.join(root, "tests", "test_kinetic.py"),
               os.path.join(root, "tests", "fsx")])
    suites_ok = r2.returncode == 0

    # 4. dependency-matrix + size compliance gate must print MANIFEST COMPLETE.
    r3 = _run(["python", os.path.join(root, "scripts", "emit_manifest.py")])
    emit_ok = r3.returncode == 0 and "MANIFEST COMPLETE" in r3.stdout

    with open(os.path.join(root, "manifest.json")) as fh:
        manifest = json.load(fh)
    dp = dependency_problems(manifest)
    manifest_ok = not dp
    sp = size_problems(os.path.join(root, "src"), manifest.get("source_cap_bytes"))
    size_cap_ok = not sp

    report = {
        "project": "gale-ledge",
        "install_ok": bool(install_ok),
        "colib_passed": col_passed,
        "col_suite_ok": bool(col_ok),
        "suites_ok": bool(suites_ok),
        "asyncfs_ok": bool(suites_ok),
        "manifest_ok": bool(manifest_ok and emit_ok),
        "size_cap_ok": bool(size_cap_ok),
        "emit_print": bool(emit_ok),
    }
    with open(os.path.join(out, "answer.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/solve.py

# --- 5. Run the driver for real to produce the deliverables. ---
python3 /app/solve.py
grep -q "5 passed" /app/colib.log && echo "oracle: col suite confirmed 5 passed"
