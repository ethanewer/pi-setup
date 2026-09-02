#!/bin/bash
# Verifier for moss-graph (executes-deliverable).
# Requires /app/solve.py. Runs the deliverable on the visible case and on every
# /tests/hidden/* case, comparing JSON outputs against the committed expected
# results. Writes reward (1 = all pass, 0 = any fail) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

if python3 - <<'PY'
import json, subprocess, os

def load(p):
    with open(p) as f:
        return json.load(f)

def close(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b
    if isinstance(a, str) and isinstance(b, str):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) <= 1e-6
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(close(a[k], b[k]) for k in b)
    return False

def run_case(args, out):
    return subprocess.run(["python3", "/app/solve.py"] + args +
                          ["--output", out], capture_output=True).returncode == 0

def check(args, want_path, out):
    if not run_case(args, out):
        return False
    try:
        return close(load(out), load(want_path))
    except Exception:
        return False

fails = []

# Visible case.
if not check(["--graph", "/app/graph.csv", "--values", "/app/values.csv",
              "--intervention", "left=10"],
             "/tests/expected.json", "/tmp/vis.json"):
    fails.append("visible")

# Deliverable output file: /app/answer.json must exist with the correct
# content for the visible input.
if os.path.exists("/app/answer.json"):
    if not close(load("/app/answer.json"), load("/tests/expected.json")):
        fails.append("answer.json-content")
else:
    fails.append("answer.json-missing")

# Hidden cases.
for case in ["case1", "case2", "case3", "case4"]:
    d = "/tests/hidden/" + case
    args = ["--graph", d + "/graph.csv", "--values", d + "/values.csv"]
    try:
        with open(d + "/intervention.txt") as f:
            iv = f.read().strip()
        if iv:
            args += ["--intervention", iv]
    except FileNotFoundError:
        pass
    if not check(args, d + "/expected.json", "/tmp/h_" + case + ".json"):
        fails.append(case)

print("fails:", fails if fails else "none")
raise SystemExit(1 if fails else 0)
PY
then
  reward=1
  echo "ALL CHECKS PASSED"
else
  reward=0
  echo "CHECKS FAILED"
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0