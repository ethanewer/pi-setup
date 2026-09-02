#!/usr/bin/env bash
# tern-delta verifier: imports the agent's /app/calib.py, re-runs calibrate on
# hidden priors/budgets, and validates /app/calibrated.json. Writes 1/0 to
# /logs/verifier/reward.txt; never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, math, os, sys

sys.path.insert(0, "/app")
failures = []

try:
    import numpy as np
except Exception as exc:  # pragma: no cover
    print("numpy unavailable:", exc)
    sys.exit(1)


def kl(a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    m = a > 0
    return float(np.sum(a[m] * np.log(a[m] / b[m])))


def check(q, p, rf, rb, tag):
    """Validate the four contract points; append failures."""
    p = np.asarray(p, dtype=float)
    p = p / p.sum()
    if not isinstance(q, np.ndarray):
        failures.append("%s: returned %s, not numpy.ndarray" % (tag, type(q)))
        return
    if q.ndim != 1 or len(q) != len(p):
        failures.append("%s: bad shape %s (want 1-D len %d)"
                        % (tag, q.shape, len(p)))
        return
    if not np.all(np.isfinite(q)):
        failures.append("%s: non-finite entries" % tag)
        return
    if not np.all(q > 0):
        failures.append("%s: non-positive entries %r" % (tag, q))
        return
    if abs(float(q.sum()) - 1.0) > 1e-9:
        failures.append("%s: sum %r != 1" % (tag, float(q.sum())))
        return
    kf = kl(q, p)
    kb = kl(p, q)
    if kf > rf + 1e-9:
        failures.append("%s: forward KL %g > budget %g" % (tag, kf, rf))
    if kb > rb + 1e-9:
        failures.append("%s: reverse KL %g > budget %g" % (tag, kb, rb))


# --- 0. module importable, calibrate present ---
try:
    import calib
    fn = getattr(calib, "calibrate", None)
    if not callable(fn):
        failures.append("calib.calibrate missing or not callable")
except Exception as exc:
    failures.append("importing /app/calib.py failed: %r" % exc)
    fn = None

# --- 1. hidden cases (distinct priors + budget pairs) from the hidden fixture ---
cases = []
cases_path = "/tests/hidden/cases.json"
if os.path.isfile(cases_path):
    try:
        cases = json.load(open(cases_path))
        if not isinstance(cases, list):
            failures.append("hidden cases.json is not a list")
            cases = []
    except Exception as exc:
        failures.append("hidden cases.json unreadable: %r" % exc)
else:
    failures.append("hidden cases.json missing")
if fn is not None:
    for case in cases:
        try:
            p = case["p"]
            rf = float(case["r_forward"])
            rb = float(case["r_backward"])
            tag = str(case.get("tag", "h-case"))
            want_p = bool(case.get("exact_p_when_zero", False))
        except Exception as exc:
            failures.append("bad hidden case entry: %r" % exc)
            continue
        try:
            q = fn(list(p), rf, rb)
        except Exception as exc:
            failures.append("%s: calibrate raised %r" % (tag, exc))
            continue
        check(q, p, rf, rb, tag)
        if want_p and isinstance(q, np.ndarray):
            pn = np.asarray(p, dtype=float)
            pn = pn / pn.sum()
            if not np.allclose(q, pn, atol=1e-12, rtol=0):
                failures.append("%s: zero-budget case must return the "
                                "normalized prior exactly" % tag)
        # also accept a numpy input to the same call
        try:
            q2 = fn(np.asarray(p, dtype=float), rf, rb)
            check(q2, p, rf, rb, tag + "-npinput")
        except Exception as exc:
            failures.append("%s: calibrate(ndarray) raised %r" % (tag, exc))

# --- 2. visible deliverable /app/calibrated.json ---
prior_path = "/app/prior.json"
cal_path = "/app/calibrated.json"
if fn is None or not os.path.isfile(prior_path) or not os.path.isfile(cal_path):
    failures.append("missing calib module, prior.json or calibrated.json")
else:
    try:
        prior = json.load(open(prior_path))
        out = json.load(open(cal_path))
        if not isinstance(out, list) or len(out) != len(prior):
            failures.append("calibrated.json shape %r" % type(out))
        else:
            check(np.asarray(out, dtype=float), prior, 0.04, 0.06, "visible")
            q = fn(prior, 0.04, 0.06)
            if not np.allclose(np.asarray(out, dtype=float), q,
                               atol=1e-9, rtol=0):
                failures.append("calibrated.json disagrees with calibrate() "
                                "on the visible prior")
    except Exception as exc:
        failures.append("calibrated.json check error: %r" % exc)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
