#!/bin/bash
# Verifier for heath-signal (executes-deliverable): executes /app/gridder.py on
# the visible fixture and on every hidden case, checks /app/answer.json against
# the visible expected output, and writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys

GRIDDER = "/app/gridder.py"
failures = []


def run_case(pts, spec, expected_path, label):
    out = "/tmp/heath_signal_out_%s.json" % label
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, GRIDDER, pts, spec, out],
            capture_output=True, text=True, timeout=120,
        )
        if r.returncode != 0 or not os.path.exists(out):
            return "%s: solver failed (rc=%s)" % (label, r.returncode)
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
    except Exception as e:
        return "%s: exception %r" % (label, e)

    if not isinstance(got, dict):
        return "%s: output not a dict" % label
    if set(got.keys()) != {"shape", "grid", "total_points", "in_box", "grid_sum"}:
        return "%s: wrong keys %s" % (label, sorted(got.keys()))
    ny, nx = want["shape"]
    if got["shape"] != [ny, nx]:
        return "%s: shape %s != %s" % (label, got["shape"], want["shape"])
    grid = got["grid"]
    if not isinstance(grid, list) or len(grid) != ny:
        return "%s: grid rows != %s" % (label, ny)
    for row in grid:
        if not isinstance(row, list) or len(row) != nx:
            return "%s: grid row length != %s" % (label, nx)
    for i in range(ny):
        for j in range(nx):
            if abs(float(grid[i][j]) - float(want["grid"][i][j])) > 1e-9:
                return "%s: grid[%d][%d] %r != %r" % (label, i, j, grid[i][j], want["grid"][i][j])
    if got["total_points"] != want["total_points"]:
        return "%s: total_points %s != %s" % (label, got["total_points"], want["total_points"])
    if got["in_box"] != want["in_box"]:
        return "%s: in_box %s != %s" % (label, got["in_box"], want["in_box"])
    if abs(float(got["grid_sum"]) - float(want["grid_sum"])) > 1e-9:
        return "%s: grid_sum %r != %r" % (label, got["grid_sum"], want["grid_sum"])
    return None


if not os.path.isfile(GRIDDER):
    failures.append("missing /app/gridder.py")
else:
    # visible case: execute the deliverable on the live supplied inputs
    res = run_case("/app/points.csv", "/app/spec.json", "/tests/expected.json", "visible")
    if res:
        failures.append(res)
    # visible-case deliverable: /app/answer.json must exist and match
    try:
        with open("/app/answer.json") as f:
            got = json.load(f)
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if got != want:
            failures.append("answer.json does not match visible expected")
    except Exception as e:
        failures.append("answer.json unreadable: %r" % e)

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir) if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            res = run_case(os.path.join(base, "points.csv"), os.path.join(base, "spec.json"),
                           os.path.join(base, "expected.json"), c)
            if res:
                failures.append(res)
    else:
        failures.append("no hidden case dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
