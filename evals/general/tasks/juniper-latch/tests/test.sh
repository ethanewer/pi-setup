#!/bin/bash
# Verifier for juniper-latch: ENFORCES the single-sanctioned-file rule (every
# file except /app/sigdeck/windowing.py must stay byte-identical to the
# release manifest), then EXECUTES the repaired package (python3 -m
# sigdeck.runner) on the visible input and on hidden telemetry cases.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Release manifest: sha256 of every file that must remain untouched.
MANIFEST__INIT="d618d7b758cd9a9d3f0eae38440e12870504e0dd6d13096845c0bc2513e30004"
MANIFEST_CODEC="1d444da6043edc68bd65a9c5b6d12e5cbeb968350e971a7459c28d035ccb5956"
MANIFEST_CONST="0d956020babca093828572e0a69f852e3ada99f6f726b9915c29f811c8c76aca"
MANIFEST_RUNNER="209231fcc9a4b20285905eed6260830cb80bd3dc1e16df8cdec9a941166c1915"
MANIFEST_INPUT="ef1a93a02d2101a4fe5465300ff7e808a697dbcaed2e397f62c9ef75e7ce62d4"

fail=0
check() { # path expected_sha
    if [ ! -f "$1" ]; then
        echo "no-modify: $1 missing" >&2
        fail=1
        return
    fi
    actual="$(sha256sum "$1" | awk '{print $1}')"
    if [ "$actual" != "$2" ]; then
        echo "no-modify: $1 was modified" >&2
        fail=1
    fi
}
check /app/sigdeck/__init__.py "$MANIFEST__INIT"
check /app/sigdeck/codec.py     "$MANIFEST_CODEC"
check /app/sigdeck/constants.py "$MANIFEST_CONST"
check /app/sigdeck/runner.py    "$MANIFEST_RUNNER"
check /app/input.csv            "$MANIFEST_INPUT"

python3 - "$fail" <<'PY'
import csv, json, math, os, subprocess, sys

fail = int(sys.argv[1])
failures = []
if fail:
    failures.append("release-manifest checksum mismatch (no-modify rule)")

LADDER = [0.0, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0]


def norm(rep):
    """Tolerant normalization; never raises on malformed agent output."""
    try:
        assert isinstance(rep, dict), "not a dict"
        assert set(rep.keys()) == {"window", "count", "rms", "rung"}, rep.keys()
        assert isinstance(rep["window"], int) and rep["window"] == 6
        assert isinstance(rep["count"], int)
        assert isinstance(rep["rms"], list) and isinstance(rep["rung"], list)
        assert len(rep["rms"]) == rep["count"] == len(rep["rung"])
        rms = [round(float(v), 4) for v in rep["rms"]]
        rung = [float(v) for v in rep["rung"]]
        assert all(r in LADDER for r in rung), "rung outside ladder"
        return (rep["count"], rms, rung)
    except Exception as e:
        raise AssertionError("malformed report: %s" % e)


def run_case(input_csv, expected_path):
    out = "/tmp/juniper_latch_out/report.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, "-m", "sigdeck.runner", input_csv, out],
            capture_output=True, text=True, timeout=120, cwd="/app",
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as fh:
            got = json.load(fh)
        with open(expected_path) as fh:
            want = json.load(fh)
        return norm(got) == norm(want)
    except Exception:
        return False


if not os.path.isfile("/app/sigdeck/windowing.py"):
    failures.append("missing /app/sigdeck/windowing.py")
else:
    if os.path.isfile("/app/input.csv") and os.path.isfile("/tests/expected.json"):
        if not run_case("/app/input.csv", "/tests/expected.json"):
            failures.append("visible case failed")
    else:
        failures.append("visible fixture missing")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            inp = os.path.join(base, "input.csv")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isfile(inp) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            # run against a scratch copy so /tests stays pristine
            scratch = "/tmp/juniper_latch_cases/%s_input.csv" % c
            try:
                os.makedirs("/tmp/juniper_latch_cases", exist_ok=True)
                with open(inp, "rb") as src, open(scratch, "wb") as dst:
                    dst.write(src.read())
            except Exception:
                failures.append("hidden '%s' unreadable" % c)
                continue
            if not run_case(scratch, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
