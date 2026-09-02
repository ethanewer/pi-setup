#!/bin/bash
# Verifier for dusk-forge: audits the 100 KB size budget of the whole
# /app/model directory, then EXECUTES the deliverable loader (/app/predict.py)
# on the shipped eval set and on hidden calibration sets, enforcing the RMSE
# release gate. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys

import numpy as np

failures = []

MODEL_DIR = "/app/model"
PREDICT = "/app/predict.py"
BUDGET = 102400  # bytes, entire /app/model directory


def audit_budget():
    if not os.path.isdir(MODEL_DIR):
        failures.append("missing /app/model directory")
        return False
    total = 0
    files = 0
    for root, dirs, names in os.walk(MODEL_DIR):
        for n in names:
            p = os.path.join(root, n)
            try:
                total += os.lstat(p).st_size
                files += 1
            except OSError:
                failures.append("unreadable artifact file %s" % p)
                return False
    if files == 0:
        failures.append("/app/model is empty")
        return False
    if total > BUDGET:
        failures.append("model artifact over budget: %d bytes > %d" % (total, BUDGET))
        return False
    print("artifact audit: %d files, %d bytes (budget %d)" % (files, total, BUDGET))
    return True


def score(eval_npz, rmse_max):
    out = "/tmp/dusk_forge_pred.npz"
    for p in (out,):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, PREDICT, MODEL_DIR, eval_npz, out],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        return False, "predict.py failed to run: %s" % e
    if r.returncode != 0:
        return False, "predict.py exited %d" % r.returncode
    try:
        got = np.load(out)["pred"]
        data = np.load(eval_npz)
        X, y = data["X"], data["y"]
    except Exception as e:
        return False, "malformed prediction output: %s" % e
    if got.shape != y.shape:
        return False, "pred shape %s != target shape %s" % (got.shape, y.shape)
    rmse = float(np.sqrt(np.mean((got.astype(np.float64) - y.astype(np.float64)) ** 2)))
    ok = rmse <= rmse_max
    return ok, "rmse %.4f (gate %.2f) %s" % (rmse, rmse_max, "OK" if ok else "FAIL")


if not os.path.isfile(PREDICT):
    failures.append("missing /app/predict.py")
else:
    size_ok = audit_budget()

    cases = []
    try:
        with open("/tests/expected.json") as fh:
            want = json.load(fh)
        cases.append(("/tests/eval_v.npz", float(want["rmse_max"]), "visible"))
    except Exception:
        failures.append("visible case config unreadable")

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        for c in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, c)
            npz = os.path.join(base, "eval.npz")
            meta = os.path.join(base, "expected.json")
            if not (os.path.isfile(npz) and os.path.isfile(meta)):
                failures.append("hidden case '%s' malformed" % c)
                continue
            try:
                with open(meta) as fh:
                    cases.append((npz, float(json.load(fh)["rmse_max"]), c))
            except Exception:
                failures.append("hidden case '%s' config unreadable" % c)
    if not cases:
        failures.append("no calibration cases to score")

    if size_ok:
        for npz, gate, name in cases:
            ok, msg = score(npz, gate)
            print("case %s: %s" % (name, msg))
            if not ok:
                failures.append("calibration case '%s' over gate" % name)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
