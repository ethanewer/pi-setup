#!/bin/bash
# Verifier for quartz-relic: EXECUTES the deliverable package /app/dotkit.
# Copies only the package to an isolated directory (so self-containment is
# enforced: /app/dotlib.py and other repo modules are unavailable), imports it
# in fresh interpreters, and runs every hidden case in /tests/hidden.
# Writes numeric reward to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# ---- no-modify guard: /app/dotlib.py must stay byte-identical ---------------
PRISTINE_DOTLIB_SHA="3c9d5a057c44cb1e2948606d1686778cb9b578f3d3c82bda73b3b544dd8e0bff"
if [ ! -f /app/dotlib.py ]; then
    echo "no-modify: /app/dotlib.py missing" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
actual_sha="$(sha256sum /app/dotlib.py | awk '{print $1}')"
if [ "$actual_sha" != "$PRISTINE_DOTLIB_SHA" ]; then
    echo "no-modify: /app/dotlib.py was modified" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# ---- the deliverable must exist and be a package ----------------------------
if [ ! -f /app/dotkit/__init__.py ]; then
    echo "deliverable: /app/dotkit is not a package (missing __init__.py)" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# ---- copy ONLY the package to an isolated location --------------------------
ISO=/tmp/iso_pkg
rm -rf "$ISO"
mkdir -p "$ISO"
cp -r /app/dotkit "$ISO/dotkit"

python3 - "$ISO" <<'PY'
import json
import math
import os
import subprocess
import sys

iso = sys.argv[1]
CASES = "/tests/hidden/cases.json"

with open(CASES) as f:
    cases = json.load(f)
if not isinstance(cases, list) or len(cases) < 2:
    print("hidden cases malformed", file=sys.stderr)
    sys.exit(1)

CHECK_SRC = r'''
import json, math, sys
sys.path.insert(0, sys.argv[1])
case = json.loads(sys.argv[2])

import dotkit
from dotkit import dot as dot2

if not callable(getattr(dotkit, "dot", None)):
    raise SystemExit("dotkit.dot is missing or not callable")
if dotkit.dot is not dot2:
    raise SystemExit("dotkit.dot and `from dotkit import dot` disagree")

def build(spec):
    seq = spec.get("seq", "list")
    data = spec["data"]
    return tuple(data) if seq == "tuple" else list(data)

ERRS = {"ValueError": ValueError, "TypeError": TypeError}

a_spec, b_spec = case["a"], case["b"]
a, b = build(a_spec), build(b_spec)
a_snapshot, b_snapshot = (tuple(a), tuple(b))

if "error" in case:
    try:
        dotkit.dot(a, b)
    except ERRS[case["error"]]:
        pass
    except Exception as e:
        raise SystemExit("expected %s, got %r" % (case["error"], e))
    else:
        raise SystemExit("expected %s, no exception raised" % case["error"])
else:
    got = dotkit.dot(a, b)
    want = case["expected"]
    if isinstance(got, bool) or not isinstance(got, (int, float)):
        raise SystemExit("dot must return a number, got %r" % (got,))
    if not math.isclose(float(got), float(want), rel_tol=1e-9, abs_tol=1e-12):
        raise SystemExit("got %r, want %r" % (got, want))

if tuple(a) != a_snapshot or tuple(b) != b_snapshot:
    raise SystemExit("dot mutated its inputs")
'''

failures = []

# The package must also import with /app on the path (published API).
r = subprocess.run(
    [sys.executable, "-I", "-c",
     "import sys; sys.path.insert(0, '/app'); import dotkit; "
     "assert callable(dotkit.dot)"],
    capture_output=True, text=True, timeout=60,
)
if r.returncode != 0:
    failures.append("import from /app failed: %s" % r.stderr.strip()[-300:])

for i, case in enumerate(cases):
    r = subprocess.run(
        [sys.executable, "-I", "-c", CHECK_SRC, iso, json.dumps(case)],
        capture_output=True, text=True, timeout=60,
    )
    if r.returncode != 0:
        failures.append("case %d failed: %s" % (i, r.stderr.strip()[-300:]))

if failures:
    print("verify failures:", failures, file=sys.stderr)
    sys.exit(1)
print("all %d hidden cases passed" % len(cases))
sys.exit(0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
