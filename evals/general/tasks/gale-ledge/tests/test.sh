#!/bin/bash
# Verifier for gale-ledge (executes-deliverable).
# Re-invokes /app/solve.py (the deliverable), re-runs every gate independently,
# checks the hidden fixtures via solve.py's `status` subcommand, and writes a
# numeric reward to /logs/verifier/reward.txt.  Must pass only when the agent
# fixed the three source bugs AND submitted a working, general driver.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

if [ ! -f /app/solve.py ] || [ ! -x /app/solve.py ]; then
  echo "missing deliverable /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import os
import re
import subprocess
import sys

failures = []

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def parse_count(text):
    for line in text.splitlines():
        m = re.search(r"(\d+) passed", line)
        if m:
            return int(m.group(1))
    return None

# ---- A. Deliverables present ----
for p in ("/app/solve.py", "/app/colib.log", "/app/answer.json"):
    if not os.path.exists(p):
        failures.append("missing artifact " + p)

# ---- B. Re-invoke the deliverable fresh (reproducibility) ----
r = run(["python", "/app/solve.py"])
if r.returncode != 0:
    failures.append("solve.py failed to re-run: " + (r.stderr or r.stdout)[-500:])
elif not os.path.exists("/app/answer.json"):
    failures.append("solve.py did not regenerate /app/answer.json")

# ---- C. Independently verify each competency gate ----
PROJ = "/app/proj"

# 1. targeted col suite + confirmed pass count in /app/colib.log
r = run(["python", "-m", "pytest", "-q", os.path.join(PROJ, "tests", "col")])
col_count = parse_count(r.stdout)
if r.returncode != 0:
    failures.append("col target suite does not pass fully")
if col_count is None:
    failures.append("could not parse col pass count")
log_text = ""
if os.path.exists("/app/colib.log"):
    log_text = open("/app/colib.log").read()
log_count = parse_count(log_text)
if log_count is None or log_count != col_count:
    failures.append("colib.log does not confirm the %s passed count" % col_count)

# 2. editable reinstall + async filesystem unit tests
r = run(["python", "-m", "pip", "install", "--no-build-isolation",
         "--quiet", "-e", PROJ])
if r.returncode != 0:
    failures.append("editable reinstall failed: " + (r.stderr or "")[-300:])
r = run(["python", "-m", "pytest", "-q", os.path.join(PROJ, "tests", "fsx")])
if r.returncode != 0:
    failures.append("async fsx suite failed on installed package")

# 3. focused scientific subset (kinetic model composition) + GC sweep (heap)
r = run(["python", "-m", "pytest", "-q",
         os.path.join(PROJ, "tests", "test_heap.py"),
         os.path.join(PROJ, "tests", "test_kinetic.py")])
if r.returncode != 0:
    failures.append("focused model/composition + GC sweep tests fail")

# whole-suite regression
r = run(["python", "-m", "pytest", "-q", os.path.join(PROJ, "tests")])
if r.returncode != 0:
    failures.append("full test suite has a regression")

# 5. script runs and prints its completion message
r = run(["python", os.path.join(PROJ, "scripts", "emit_manifest.py")])
if r.returncode != 0 or "MANIFEST COMPLETE" not in r.stdout:
    failures.append("emit_manifest did not run to completion message")

# ---- D. hard source-size cap (fixed at 3000 bytes per source file) ----
CAP = 3000
for dirpath, _dirs, files in os.walk(os.path.join(PROJ, "src")):
    for fn in files:
        full = os.path.join(dirpath, fn)
        try:
            if os.path.getsize(full) > CAP:
                failures.append("source file over cap: %s (%d)" % (full, os.path.getsize(full)))
        except OSError:
            pass

# ---- E. answer.json content ----
if os.path.exists("/app/answer.json"):
    ans = json.load(open("/app/answer.json"))
    if ans.get("colib_passed") != col_count:
        failures.append("answer.json colib_passed %r != %r" % (ans.get("colib_passed"), col_count))
    for k in ("install_ok", "col_suite_ok", "suites_ok", "manifest_ok", "size_cap_ok"):
        if not ans.get(k):
            failures.append("answer.json %s is not true" % k)

# ---- F. hidden fixtures via solve.py `status` (fresh / malformed) ----
def status(manifest, src=None):
    cmd = ["python", "/app/solve.py", "status", "--manifest", manifest]
    if src:
        cmd += ["--src", src]
    r = run(cmd)
    if r.returncode != 0:
        return None, r.stderr
    try:
        return json.loads(r.stdout), None
    except Exception as e:
        return None, str(e)

H = "/tests/hidden"
res, err = status(H + "/small/manifest.json", H + "/small/src")
if err:
    failures.append("hidden small: " + err)
elif not (res.get("manifest_ok") is True and res.get("size_cap_ok") is True):
    failures.append("hidden small: expected compliant, got " + json.dumps(res))

res, err = status(H + "/conflicting/manifest.json", H + "/conflicting/src")
if err:
    failures.append("hidden conflicting: " + err)
elif not (res.get("manifest_ok") is False and res.get("size_cap_ok") is False):
    failures.append("hidden conflicting: expected both false, got " + json.dumps(res))

res, err = status(H + "/malformed/manifest.json")
if err:
    failures.append("hidden malformed: verifier crashed: " + err)
elif res.get("manifest_ok") is not False:
    failures.append("hidden malformed: expected manifest_ok=false, got " + json.dumps(res))

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS (col count=%s)" % col_count)
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY
