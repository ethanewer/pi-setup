#!/bin/bash
# Verifier for moss-latch: re-runs the deliverable build script (twice, for
# idempotency), re-runs the untouched probe, checks the agent's probe report,
# and executes the installed grainflow module on hidden cases. Writes the
# REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of /app/probe.py (the instruction forbids modifying it).
PRISTINE_PROBE_SHA="a01d9b3820a02603a4ac7cea4a01ff9f1eb4b9066e4f99adfcfcec1d7adcf884"

probe_ok=1
if [ ! -f /app/probe.py ]; then
    echo "no-modify: /app/probe.py missing" >&2
    probe_ok=0
else
    actual="$(sha256sum /app/probe.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_PROBE_SHA" ]; then
        echo "no-modify: /app/probe.py was modified" >&2
        probe_ok=0
    fi
fi

# --- execute the /app/build.sh deliverable, twice (idempotency) ---
build_ok=1
bash /app/build.sh >/tmp/ml_build1.log 2>&1 || build_ok=0
bash /app/build.sh >/tmp/ml_build2.log 2>&1 || build_ok=0

python3 - "$build_ok" "$probe_ok" <<'PY'
import json
import math
import os
import subprocess
import sys

build_ok = int(sys.argv[1])
probe_ok = int(sys.argv[2])
failures = []

if not build_ok:
    failures.append("/app/build.sh failed (exit != 0 on first or second run)")

if not probe_ok:
    failures.append("/app/probe.py missing or modified (no-modify rule)")

TOL = 1e-9


def close_list(got, want):
    got = [float(x) for x in got]
    want = [float(x) for x in want]
    return len(got) == len(want) and all(
        math.isfinite(a) and abs(a - b) <= TOL for a, b in zip(got, want)
    )


try:
    import numpy
    if numpy.__version__.split(".")[0] != "2":
        failures.append("installed numpy is not 2.x: %s" % numpy.__version__)
except Exception as e:
    failures.append("numpy import failed: %r" % (e,))

# --- import the deliverable-installed module from a neutral cwd ---
mod = None
if not failures:
    try:
        r = subprocess.run(
            [sys.executable, "-c",
             "import grainflow, json; print(json.dumps("
             "{'file': grainflow.__file__,"
             " 'hann8': [float(x) for x in grainflow.hann(8)]}))"],
            capture_output=True, text=True, timeout=120, cwd="/tmp",
        )
        if r.returncode != 0:
            failures.append("import grainflow failed: %s" % r.stderr.strip()[-400:])
        else:
            info = json.loads(r.stdout)
            if "site-packages" not in info["file"]:
                failures.append(
                    "grainflow is not a regular site-packages install: %s"
                    % info["file"]
                )
    except Exception as e:
        failures.append("import probe crashed: %r" % (e,))

# --- re-run /app/probe.py and compare with the visible expectation ---
if not failures:
    out = "/tmp/ml_probe_recheck.json"
    r = subprocess.run(
        [sys.executable, "/app/probe.py", out],
        capture_output=True, text=True, timeout=120, cwd="/tmp",
    )
    if r.returncode != 0:
        failures.append("probe.py re-run failed: %s" % r.stderr.strip()[-400:])
    else:
        try:
            got = json.load(open(out))
            want = json.load(open("/tests/expected.json"))
        except Exception as e:
            failures.append("probe output unreadable: %r" % (e,))
        else:
            for key in ("numpy_major", "hann_8", "hann_2", "ramp_6", "ramp_0"):
                if key not in got:
                    failures.append("probe output missing key %s" % key)
                elif key == "numpy_major":
                    if got[key] != want[key]:
                        failures.append("numpy_major %r != 2" % (got[key],))
                elif not close_list(got[key], want[key]):
                    failures.append("probe %s mismatch" % key)

# --- the agent's /app/probe_out.json deliverable must match too ---
if not failures:
    if not os.path.isfile("/app/probe_out.json"):
        failures.append("missing deliverable /app/probe_out.json")
    else:
        try:
            got = json.load(open("/app/probe_out.json"))
            want = json.load(open("/tests/expected.json"))
            for key in ("numpy_major", "hann_8", "hann_2", "ramp_6", "ramp_0"):
                if key not in got:
                    failures.append("probe_out.json missing key %s" % key)
                elif key == "numpy_major":
                    if got[key] != want[key]:
                        failures.append("probe_out numpy_major %r != 2" % (got[key],))
                elif not close_list(got[key], want[key]):
                    failures.append("probe_out %s mismatch" % key)
        except Exception as e:
            failures.append("probe_out.json unreadable: %r" % (e,))

# --- hidden cases: execute the installed module on unseen inputs ---
if not failures:
    hidden_dir = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hidden_dir)
                   if os.path.isfile(os.path.join(hidden_dir, d, "case.json")))
    if not cases:
        failures.append("no hidden cases present")
    for name in cases:
        with open(os.path.join(hidden_dir, name, "case.json")) as fh:
            case = json.load(fh)
        for i, call in enumerate(case.get("calls", [])):
            func = call.get("func")
            args = call.get("args", [])
            snippet = (
                "import grainflow, json, sys\n"
                "f = getattr(grainflow, %r)\n"
                "try:\n"
                "    r = f(*%r)\n"
                "    print(json.dumps({'ok': True,"
                " 'type': type(r).__name__,"
                " 'dtype': str(getattr(r, 'dtype', '')),"
                " 'vals': [float(x) for x in r]}))\n"
                "except ValueError as e:\n"
                "    print(json.dumps({'ok': False, 'err': 'ValueError'}))\n"
            ) % (func, args)
            r = subprocess.run(
                [sys.executable, "-c", snippet],
                capture_output=True, text=True, timeout=120, cwd="/tmp",
            )
            if r.returncode != 0:
                failures.append(
                    "hidden %s call %d (%s%r) crashed: %s"
                    % (name, i, func, args, r.stderr.strip()[-200:])
                )
                continue
            try:
                res = json.loads(r.stdout)
            except Exception as e:
                failures.append("hidden %s call %d: unreadable result %r" % (name, i, e))
                continue
            if "expect_error" in call:
                if res.get("ok") is not False or res.get("err") != call["expect_error"]:
                    failures.append(
                        "hidden %s call %d (%s%r): expected %s"
                        % (name, i, func, args, call["expect_error"])
                    )
                continue
            if res.get("ok") is not True:
                failures.append(
                    "hidden %s call %d (%s%r): unexpected error %s"
                    % (name, i, func, args, res.get("err"))
                )
                continue
            if res.get("type") != "ndarray" or res.get("dtype") != "float64":
                failures.append(
                    "hidden %s call %d (%s%r): not a float64 ndarray (%s/%s)"
                    % (name, i, func, args, res.get("type"), res.get("dtype"))
                )
                continue
            if not close_list(res.get("vals", []), call.get("expected", [])):
                failures.append(
                    "hidden %s call %d (%s%r): values mismatch"
                    % (name, i, func, args)
                )

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward"
exit 0
