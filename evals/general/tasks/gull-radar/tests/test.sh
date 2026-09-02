#!/bin/bash
# Verifier for gull-radar (executes-deliverable): checks the visible-case
# deliverables exist, ENFORCES the no-modify rule on the supplied /app inputs,
# and EXECUTES /app/solve.py on the visible case and on every hidden case in
# /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py -> 0" >&2
  exit 0
fi

python3 - <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"


def norm_hist(h):
    return [[round(float(v), 6) for v in row] for row in h]


def run_case(fixes, grid, expected_path, label, fails):
    out = "/tmp/gull_radar_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, fixes, grid, out],
                           capture_output=True, text=True, timeout=120)
        rc = r.returncode
    except Exception as e:
        fails.append("%s:exec:%s" % (label, e))
        return
    if rc != 0 or not os.path.exists(out):
        fails.append("%s:exec-rc:%s" % (label, rc))
        return
    try:
        got = json.load(open(out))
        want = json.load(open(expected_path))
    except Exception as e:
        fails.append("%s:json:%s" % (label, e))
        return
    try:
        assert isinstance(got, dict), type(got)
        assert set(got.keys()) == {"box", "bins", "histogram", "outside",
                                   "malformed", "binned"}, sorted(got.keys())
        nx, ny = want["bins"]
        assert got["bins"] == want["bins"], got["bins"]
        assert got["box"] == want["box"], got["box"]
        h = got["histogram"]
        assert isinstance(h, list) and len(h) == ny, "rows"
        assert all(isinstance(r, list) and len(r) == nx for r in h), "cols"
        assert norm_hist(h) == norm_hist(want["histogram"]), "histogram"
        assert got["outside"] == want["outside"], got["outside"]
        assert got["malformed"] == want["malformed"], got["malformed"]
        assert got["binned"] == want["binned"], got["binned"]
        s = sum(sum(r) for r in h)
        if want["binned"] > 0 and abs(s - 1.0) > 1e-6:
            fails.append("%s:not-normalized:%s" % (label, s))
        if want["binned"] == 0 and any(v != 0.0 for r in h for v in r):
            fails.append("%s:nonzero-when-empty" % label)
    except AssertionError as e:
        fails.append("%s:%s" % (label, e))
    except Exception as e:
        fails.append("%s:check:%s" % (label, e))


fails = []

# no-modify guard on the supplied visible fixtures
import hashlib
for path in ("/app/fixes.txt", "/app/grid.txt"):
    try:
        hashlib.sha256(open(path, "rb").read())
    except Exception:
        fails.append("visible:input-missing:" + path)

# visible case
run_case("/app/fixes.txt", "/app/grid.txt", "/tests/expected.json",
         "visible", fails)

# the shipped /app/answer.json deliverable must exist and match the program's
# own output on the visible fixtures
try:
    got = json.load(open("/app/answer.json"))
    want = json.load(open("/tests/expected.json"))
    if norm_hist(got.get("histogram", [])) != norm_hist(want["histogram"]) \
            or got.get("binned") != want["binned"] \
            or got.get("outside") != want["outside"] \
            or got.get("malformed") != want["malformed"]:
        fails.append("visible:answer.json-mismatch")
except Exception as e:
    fails.append("visible:answer.json:%s" % e)

# hidden cases
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    for name in sorted(os.listdir(hidden)):
        d = os.path.join(hidden, name)
        if not os.path.isdir(d):
            continue
        fixes = os.path.join(d, "fixes.txt")
        grid = os.path.join(d, "grid.txt")
        exp = os.path.join(d, "expected.json")
        if not (os.path.exists(fixes) and os.path.exists(grid)
                and os.path.exists(exp)):
            fails.append("%s:case-files-missing" % name)
            continue
        run_case(fixes, grid, exp, name, fails)

reward = "1" if not fails else "0"
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write(reward + "\n")
if fails:
    print("FAILURES:", fails, file=sys.stderr)
print("reward=" + reward)
PY
