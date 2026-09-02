#!/bin/bash
# Verifier for sable-ray (executes-deliverable).
#
# Executes the deliverable /app/reimpl.py against the native target
# /app/target/raycaster on the visible fixture and on every hidden grid under
# /tests/hidden, requiring byte-identical stdout on every case. Every hidden
# case also carries expected.txt (recorded from the pristine binary); the
# native binary itself must reproduce it, which catches any tampering with
# the protected fixture without depending on a build-specific hash. Checks
# /app/notes.md exists and is substantive. Writes REWARD to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import os
import subprocess
import sys

REIMPL = "/app/reimpl.py"
NOTES = "/app/notes.md"
NATIVE = "/app/target/raycaster"
failures = []


def run(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception as e:
        return None, str(e).encode()


def case_ok(grid, expected_path):
    rc_n, out_n = run([NATIVE, grid])
    rc_r, out_r = run([sys.executable, REIMPL, grid])
    if rc_n != 0:
        failures.append("native target failed on %s (rc=%s)" % (grid, rc_n))
        return
    if expected_path and os.path.isfile(expected_path):
        with open(expected_path, "rb") as fh:
            want = fh.read()
        if out_n != want:
            failures.append("native target deviates from recorded expected on %s "
                            "(fixture tampered?)" % grid)
            return
    if rc_r != 0:
        failures.append("reimpl.py failed on %s (rc=%s)" % (grid, rc_r))
        return
    if out_r != out_n:
        failures.append("reimpl.py stdout differs from native on %s" % grid)


# deliverables present
if not os.path.isfile(REIMPL):
    failures.append("missing /app/reimpl.py")
if not os.path.isfile(NOTES):
    failures.append("missing /app/notes.md")
elif os.path.getsize(NOTES) < 200:
    failures.append("/app/notes.md too thin to be a real write-up")
if not os.path.isfile(NATIVE) or not os.access(NATIVE, os.X_OK):
    failures.append("native fixture /app/target/raycaster missing/not executable")

# the reimplementation must be pure Python: no reference to the native target
if os.path.isfile(REIMPL):
    with open(REIMPL, "rb") as fh:
        src = fh.read().decode("utf-8", "replace")
    low = src.lower()
    for bad in ("raycaster", "/app/target", "subprocess", "ctypes", "popen",
                "os.system", "os.exec"):
        if bad in low:
            failures.append("reimpl.py references forbidden facility %r" % bad)

# visible fixture
if not failures:
    case_ok("/app/scene/grid.txt", None)

# hidden cases: reimpl must byte-match the native binary, and the native
# binary must itself reproduce the recorded expected output
hidden = "/tests/hidden"
cases = sorted(d for d in os.listdir(hidden)
               if os.path.isdir(os.path.join(hidden, d))) if os.path.isdir(hidden) else []
if len(cases) < 2:
    failures.append("too few hidden cases")
for c in cases:
    grid = os.path.join(hidden, c, "grid.txt")
    exp = os.path.join(hidden, c, "expected.txt")
    if not os.path.isfile(grid):
        failures.append("hidden case %s missing grid.txt" % c)
        continue
    case_ok(grid, exp)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
