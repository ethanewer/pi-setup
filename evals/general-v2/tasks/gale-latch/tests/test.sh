#!/bin/bash
# Verifier for gale-latch (executes-deliverable).
#
# Executes /app/port.sh, independently re-runs the ported build configuration
# (python3 /app/src/gridops/setup.py build_ext --inplace), guards that the
# removed legacy APIs are gone, then executes the compiled gridcore module on
# the visible sanity case and on every hidden case in /tests/hidden.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json
import os
import subprocess
import sys

fails = []

# ---- execute deliverable /app/port.sh ----
try:
    r = subprocess.run(["bash", "/app/port.sh"], capture_output=True,
                       text=True, timeout=240)
    if r.returncode != 0:
        fails.append("port.sh exit %d: %s" % (r.returncode, r.stderr[-400:]))
except Exception as e:
    fails.append("port.sh run failed: %r" % (e,))

# ---- the ported build config itself must work (not bypassed) ----
try:
    r = subprocess.run(
        ["python3", "/app/src/gridops/setup.py", "build_ext", "--inplace"],
        cwd="/app/src/gridops", capture_output=True, text=True, timeout=240,
    )
    if r.returncode != 0:
        fails.append("setup.py build exit %d: %s"
                     % (r.returncode, r.stderr[-400:]))
except Exception as e:
    fails.append("setup.py build run failed: %r" % (e,))

# ---- removed legacy numpy APIs must no longer be used ----
try:
    with open("/app/src/gridops/setup.py") as fh:
        setup_src = fh.read()
    with open("/app/src/gridops/gridcore.pyx") as fh:
        pyx_src = fh.read()
    if "numpy.distutils" in setup_src:
        fails.append("setup.py still uses numpy.distutils (removed in numpy 2.0)")
    if "PyArray_FromDims" in pyx_src:
        fails.append("gridcore.pyx still calls PyArray_FromDims (removed C API)")
except Exception as e:
    fails.append("source read failed: %r" % (e,))

sys.path.insert(0, "/app/src/gridops")
try:
    import numpy as np
    import gridcore
except Exception as e:
    fails.append("import gridcore failed: %r" % (e,))
    print("verify failures:", fails)
    sys.exit(1)


def close(a, b):
    try:
        a = np.asarray(a, dtype=float)
        b = np.asarray(b, dtype=float)
        return a.shape == b.shape and bool(np.allclose(a, b, rtol=1e-9, atol=1e-12))
    except Exception:
        return False


# ---- visible sanity: contract semantics on the live module ----
try:
    if not close(gridcore.rms([[1.0, 2.0], [3.0, 4.0]]), (30.0 / 4.0) ** 0.5):
        fails.append("visible rms wrong: %r" % (gridcore.rms([[1.0, 2.0], [3.0, 4.0]]),))
    got = gridcore.scale([1.0, -2.0, 3.0], 2.5)
    if not close(got, [2.5, -5.0, 7.5]):
        fails.append("visible scale wrong: %r" % (got,))
except Exception as e:
    fails.append("visible case crashed: %r" % (e,))

# ---- hidden cases: genuinely distinct inputs with their own expecteds ----
hidden_dir = "/tests/hidden"
if not os.path.isdir(hidden_dir):
    fails.append("/tests/hidden missing")
else:
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        fails.append("no hidden cases present")
    for case in cases:
        d = os.path.join(hidden_dir, case)
        try:
            with open(os.path.join(d, "input.json")) as fh:
                inp = json.load(fh)
            with open(os.path.join(d, "expected.json")) as fh:
                exp = json.load(fh)
            if not isinstance(inp, dict) or "op" not in inp:
                raise ValueError("bad input.json")
            if not isinstance(exp, dict) or "value" not in exp:
                raise ValueError("bad expected.json")
        except Exception as e:
            fails.append("hidden '%s' unreadable: %r" % (case, e))
            continue
        try:
            if inp["op"] == "rms":
                got = gridcore.rms(inp["grid"])
            elif inp["op"] == "scale":
                vec = np.array(inp["vec"], dtype=float)
                snap = vec.copy()
                got = gridcore.scale(vec, float(inp["factor"]))
                if not close(vec, snap):
                    fails.append("hidden '%s': input array was modified" % case)
                    continue
            else:
                fails.append("hidden '%s': unknown op %r" % (case, inp["op"]))
                continue
            if not close(got, exp["value"]):
                fails.append("hidden '%s': got %r want %r" % (case, got, exp["value"]))
        except Exception as e:
            fails.append("hidden '%s': %r" % (case, e))

print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward"
exit 0
