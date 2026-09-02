#!/bin/bash
# Verifier for basalt-lattice: checks the visible-case deliverables and
# EXECUTES the deliverable solver (/app/solver.py) on the visible case and on
# every hidden case in /tests/hidden, comparing directed edge sets (exact) and
# OLS slopes (within tolerance). Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (no-modify rule).
PRISTINE_SAMPLES_SHA="5874099e6be7d0b8b1a32940c90d77894408f825814aa290695bba9ec14739ec"
PRISTINE_SPEC_SHA="9355e3c27b9565667ab58d3398e03889fe111cad12ec219bc9268cb867dac77b"

export PRISTINE_SAMPLES_SHA PRISTINE_SPEC_SHA

python3 - <<'PY'
import csv, json, os, subprocess, sys

SOLVE = "/app/solver.py"
failures = []

if os.environ.get("PRISTINE_SAMPLES_SHA") != "5874099e6be7d0b8b1a32940c90d77894408f825814aa290695bba9ec14739ec":
    failures.append("no-modify: /app/samples.csv changed or missing")
if os.environ.get("PRISTINE_SPEC_SHA") != "9355e3c27b9565667ab58d3398e03889fe111cad12ec219bc9268cb867dac77b":
    failures.append("no-modify: /app/spec.json changed or missing")


def run_case(samples, spec, expected_path):
    """Execute the deliverable solver on one case and validate its outputs."""
    eout, fout = "/tmp/edges_out.csv", "/tmp/fit_out.csv"
    for p in (eout, fout):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, SOLVE, samples, spec, eout, fout],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("solver crashed: %r" % e)
        return False
    if r.returncode != 0:
        failures.append("solver exit %d: %s" % (r.returncode, r.stderr[-300:]))
        return False
    try:
        with open(eout) as f:
            erows = list(csv.reader(f))
        with open(fout) as f:
            frows = list(csv.reader(f))
        with open(expected_path) as f:
            want = json.load(f)
    except Exception as e:
        failures.append("output unreadable: %r" % e)
        return False
    if not erows or erows[0] != ["parent", "child"]:
        failures.append("bad edges header")
        return False
    got_edges = sorted((r[0], r[1]) for r in erows[1:] if len(r) >= 2)
    want_edges = sorted(tuple(e) for e in want["edges"])
    if got_edges != want_edges:
        failures.append("edge set mismatch: got %s want %s" % (got_edges, want_edges))
        return False
    if not frows or frows[0] != ["parent", "child", "slope"]:
        failures.append("bad fit header")
        return False
    got_slope = {}
    for r in frows[1:]:
        if len(r) >= 3:
            got_slope[(r[0], r[1])] = float(r[2])
    for key, ws in want["slopes"].items():
        p, c = key.split("|")
        if (p, c) not in got_slope:
            failures.append("missing slope for %s" % key)
            return False
        if abs(got_slope[(p, c)] - ws) > 2e-6:
            failures.append("slope mismatch %s: got %r want %r" % (key, got_slope[(p, c)], ws))
            return False
    return True


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solver.py")
else:
    # visible case: execute solver on the live fixtures
    if not (os.path.isfile("/app/samples.csv") and os.path.isfile("/app/spec.json")):
        failures.append("visible fixtures missing")
    elif not run_case("/app/samples.csv", "/app/spec.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # visible-case deliverables must exist and match the visible expected
    try:
        with open("/app/recovered_edges.csv") as f:
            got_e = sorted((r[0], r[1]) for r in list(csv.reader(f))[1:] if len(r) >= 2)
        with open("/tests/expected.json") as f:
            want_e = sorted(tuple(e) for e in json.load(f)["edges"])
        if got_e != want_e:
            failures.append("/app/recovered_edges.csv does not match expected")
    except Exception as e:
        failures.append("/app/recovered_edges.csv unreadable: %r" % e)
    try:
        with open("/app/fit.csv") as f:
            rows = list(csv.reader(f))
        if not rows or rows[0] != ["parent", "child", "slope"]:
            failures.append("/app/fit.csv bad header")
        else:
            got_s = {(r[0], r[1]): float(r[2]) for r in rows[1:] if len(r) >= 3}
            with open("/tests/expected.json") as f:
                want_s = json.load(f)["slopes"]
            for key, ws in want_s.items():
                p, c = key.split("|")
                if (p, c) not in got_s or abs(got_s[(p, c)] - ws) > 2e-6:
                    failures.append("/app/fit.csv slope mismatch %s" % key)
                    break
    except Exception as e:
        failures.append("/app/fit.csv unreadable: %r" % e)

    # hidden cases: distinct datasets requiring the exact documented procedure
    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(os.listdir(hidden))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden, c)
            if not all(os.path.isfile(os.path.join(base, x)) for x in
                       ("samples.csv", "spec.json", "expected.json")):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(os.path.join(base, "samples.csv"),
                            os.path.join(base, "spec.json"),
                            os.path.join(base, "expected.json")):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

status=$?
if [ $status -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
