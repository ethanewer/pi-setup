#!/bin/bash
# Verifier for saffron-chain (executes-deliverable).
# /app/sample.py must be a real Metropolis sampler. We execute it on the visible
# config (/app/target.txt) and on every /tests/hidden/case*.conf, checking:
#   count == n | all samples inside support | mean & variance match the exact
#   truncated-normal moments | reproducible under a fixed seed.
# Writes reward (1 = all pass, 0 = any fail) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/sample.py ]; then
  echo "missing deliverable /app/sample.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import json
import math
import os
import subprocess
import sys

DELIVERABLE = "/app/sample.py"
VISIBLE_CFG = "/app/target.txt"
REFPATH = "/tests/hidden/reference.json"
REP = 4.0  # MCMC autocorrelation factor over iid counts

with open(REFPATH) as f:
    refs = json.load(f)

failures = []

def run_case(cfg, out):
    r = subprocess.run(["python3", DELIVERABLE] + cfg,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, r.stderr.strip()
    if not os.path.exists(out):
        return None, "missing output " + out
    with open(out) as f:
        return [float(x) for x in f.read().split()], None

def close(a, b, tol):
    return abs(a - b) <= tol

def check_case(name, args, out, ref):
    vals, err = run_case(args, out)
    if err:
        failures.append("%s: runtime error: %s" % (name, err)); return
    with open(out) as f:
        first = f.read()
    vals2, err2 = run_case(args, out)
    if err2:
        failures.append("%s: runtime error (2nd run): %s" % (name, err2)); return
    with open(out) as f:
        second = f.read()
    if first != second:
        failures.append("%s: not reproducible under fixed seed" % name); return

    n = len(vals)
    if n != ref["n"]:
        failures.append("%s: expected n=%d got %d draws" % (name, ref["n"], n)); return
    lo, hi = ref["support"][0], ref["support"][1]
    for x in vals:
        if x < lo - 1e-9 or x > hi + 1e-9:
            failures.append("%s: sample %.6f outside support" % (name, x)); return

    mean = sum(vals) / n
    var = sum((x - mean) ** 2 for x in vals) / (n - 1)
    mean_tol = max(0.05, 8.0 * math.sqrt(REP * ref["variance"] / n))
    var_tol = max(0.05, 8.0 * math.sqrt(REP) * ref["variance"] * math.sqrt(2.0 / n))
    ok = close(mean, ref["mean"], mean_tol) and close(var, ref["variance"], var_tol)
    if not ok:
        failures.append(
            "%s: mean=%.4f (want %.4f tol %.4f) var=%.4f (want %.4f tol %.4f)"
            % (name, mean, ref["mean"], mean_tol, var, ref["variance"], var_tol))
    else:
        print("PASS %-8s n=%d mean=%.4f var=%.4f" % (name, n, mean, var))

# --- Visible case: default CLI (no args) must write /app/samples.txt ---
r = subprocess.run(["python3", DELIVERABLE], capture_output=True, text=True)
if r.returncode != 0:
    failures.append("visible: runtime failure: " + r.stderr.strip())
elif not os.path.exists("/app/samples.txt"):
    failures.append("visible: /app/samples.txt not produced with default args")
else:
    ref = refs["target"]
    with open("/app/samples.txt") as f:
        vis = [float(x) for x in f.read().split()]
    n = len(vis)
    if n != ref["n"]:
        failures.append("visible: expected %d draws, got %d" % (ref["n"], n))
    else:
        lo, hi = ref["support"][0], ref["support"][1]
        mean = sum(vis) / n
        var = sum((x - mean) ** 2 for x in vis) / (n - 1)
        mean_tol = max(0.05, 8.0 * math.sqrt(REP * ref["variance"] / n))
        var_tol = max(0.05, 8.0 * math.sqrt(REP) * ref["variance"] * math.sqrt(2.0 / n))
        in_sup = all(lo - 1e-9 <= x <= hi + 1e-9 for x in vis)
        if in_sup and close(mean, ref["mean"], mean_tol) and close(var, ref["variance"], var_tol):
            print("PASS visible n=%d mean=%.4f var=%.4f" % (n, mean, var))
        else:
            failures.append("visible: support/mean/var mismatch (mean %.4f var %.4f)"
                            % (mean, var))

# --- Hidden cases: run the deliverable on fresh configs ---
os.makedirs("/tmp/hidden", exist_ok=True)
for hf in sorted(os.listdir("/tests/hidden")):
    if not hf.endswith(".conf"):
        continue
    cbase = hf[:-5]
    if cbase not in refs:
        failures.append("no reference for hidden %s" % cbase)
        continue
    check_case(cbase, ["/tests/hidden/%s" % hf, "/tmp/hidden/%s.txt" % cbase],
               "/tmp/hidden/%s.txt" % cbase, refs[cbase])

# /app/target.txt must be pristine (agent must not modify the input).
with open(VISIBLE_CFG) as f:
    if "seed=812" not in f.read():
        failures.append("visible config was modified")

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)
print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY