#!/bin/bash
# Verifier for dusk-wicket: EXECUTES the deliverable linter CLI
# (/app/lintkit/lint.py) on hidden minipy sources, recomputes the expected
# findings independently (/tests/reference.py, a fully self-contained second
# implementation of the three rules + suppression semantics), compares exact
# JSON, and exercises the incremental cache: fresh-cache first run must be all
# cache misses, the second run all hits, and a content mutation must
# invalidate.  Writes 1/0 to /logs/verifier/reward.txt on every exit path.
set -u
mkdir -p /logs/verifier
TIMEOUT_CMD=$(command -v timeout || true); [ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""
overall=1
finalize_reward() { if [ "${overall:-0}" = "1" ]; then printf 1 > /logs/verifier/reward.txt; else printf 0 > /logs/verifier/reward.txt; fi; }
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt
log() { echo "dusk-wicket verify: $*" >&2; }

python3 - <<'PY'
import glob
import json
import os
import re
import subprocess
import sys

LINT_PY = "/app/lintkit/lint.py"
RULES = [
    "/app/rules/forbid_call.py",
    "/app/rules/shadow_var.py",
    "/app/rules/mut_default.py",
]
REFERENCE = "/tests/reference.py"
HIDDEN = "/tests/hidden"
CACHE = "/app/lintcache"

failures = []


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True,
                              timeout=120, **kw)
    except Exception as exc:
        failures.append("running %r raised %s" % (cmd, exc))
        return None


def parse_stdout(proc, label):
    if proc is None or proc.returncode != 0:
        failures.append("%s: CLI failed (rc=%s)" % (
            label, proc.returncode if proc else "?"))
        return None
    try:
        return json.loads(proc.stdout)
    except Exception as exc:
        failures.append("%s: stdout not JSON: %s" % (label, exc))
        return None


def stats_of(proc):
    stats = {}
    for line in (proc.stderr or "").splitlines():
        if line.startswith("cache:"):
            key, _, value = line.partition("=")
            stats[key[len("cache:"):]] = value
    return stats


# ---- 0. deliverables exist and are non-empty ---------------------------
for path in [LINT_PY] + RULES:
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        failures.append("missing/empty deliverable %s" % path)

files = sorted(glob.glob(os.path.join(HIDDEN, "*.mpy")))
if not files:
    failures.append("no hidden minipy sources found")

# ---- 1. independent reference run --------------------------------------
r = run([sys.executable, REFERENCE] + files)
if r is None or r.returncode != 0:
    failures.append("reference failed to run")
    expected = {}
else:
    try:
        expected = json.loads(r.stdout)
    except Exception as exc:
        failures.append("reference output not JSON: %s" % exc)
        expected = {}

# ---- 2. core behaviour: no-cache run must match reference exactly ------
if files:
    r = run([sys.executable, LINT_PY, "--no-cache"] + files)
    actual = parse_stdout(r, "core run")
    if actual is not None:
        for path in files:
            if actual.get(path) != expected.get(path):
                failures.append(
                    "findings mismatch for %s" % os.path.basename(path))
        if sorted(actual.keys()) != sorted(expected.keys()):
            failures.append("file key set mismatch")

# ---- 3. cache: fresh dir, run twice, verify hit/miss, names, values -----
if files and not failures:
    for f in glob.glob(os.path.join(CACHE, "*")):
        try:
            os.remove(f)
        except OSError:
            pass
    r1 = run([sys.executable, LINT_PY, "--stats", "--cache-dir", CACHE] + files)
    a1 = parse_stdout(r1, "cache run 1")
    s1 = stats_of(r1)
    if s1.get("misses") != str(len(files)) or s1.get("hits") != "0":
        failures.append("cache run1 stats wrong: hits=%s misses=%s (want 0/%d)"
                        % (s1.get("hits"), s1.get("misses"), len(files)))
    entries = [p for p in glob.glob(os.path.join(CACHE, "*.json"))
               if os.path.isfile(p)]
    key_re = re.compile(r"^[0-9a-f]{64}_[0-9a-f]{64}\.json$")
    if len(entries) != len(files) or not all(
            key_re.match(os.path.basename(p)) for p in entries):
        failures.append("cache entry files wrong (%d entries)" % len(entries))
    for p in entries:
        try:
            with open(p) as fh:
                cached = json.load(fh)
        except Exception as exc:
            failures.append("cache entry unreadable: %s" % exc)
            continue
        # entry content must equal the expected findings of some input file
        if cached not in expected.values():
            failures.append("cache entry content not an expected finding list")

    r2 = run([sys.executable, LINT_PY, "--stats", "--cache-dir", CACHE] + files)
    a2 = parse_stdout(r2, "cache run 2")
    s2 = stats_of(r2)
    if s2.get("hits") != str(len(files)) or s2.get("misses") != "0":
        failures.append("cache run2 stats wrong: hits=%s misses=%s (want %d/0)"
                        % (s2.get("hits"), s2.get("misses"), len(files)))
    if a1 is not None and a2 is not None and a1 != a2:
        failures.append("cached output differs between runs")
    if a1 is not None:
        for path in files:
            if a1.get(path) != expected.get(path):
                failures.append("cached findings mismatch for %s"
                                % os.path.basename(path))

# ---- 4. cache invalidation on content change ---------------------------
if files and not failures:
    src = files[0]
    with open(src, "r", encoding="utf-8") as fh:
        original = fh.read()
    tmp = "/tmp/inval.mpy"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(original)
    # identical content must reuse the cache even under a different path
    r3 = run([sys.executable, LINT_PY, "--stats", "--cache-dir", CACHE, tmp])
    s3 = stats_of(r3)
    if s3.get("misses") != "0" or s3.get("hits") != "1":
        failures.append("identical content must be a cache hit: %s" % s3)
    modified = original + "\ndef late():\n    system(\"boom\")\n"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(modified)
    r4 = run([sys.executable, LINT_PY, "--stats", "--cache-dir", CACHE, tmp])
    a4 = parse_stdout(r4, "invalidation run")
    s4 = stats_of(r4)
    if s4.get("misses") != "1" or s4.get("hits") != "0":
        failures.append("content change must invalidate the cache: %s" % s4)
    if a4 is not None:
        rref = run([sys.executable, REFERENCE, tmp])
        if rref is not None and rref.returncode == 0:
            want = json.loads(rref.stdout).get(tmp)
            if a4.get(tmp) != want:
                failures.append("invalidated findings differ from reference")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then overall=1; else overall=0; fi
finalize_reward
exit 0