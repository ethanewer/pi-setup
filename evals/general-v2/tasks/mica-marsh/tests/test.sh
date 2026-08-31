#!/bin/bash
# mica-marsh verifier. Imports the delivered extract_rows from
# /app/probe_mlp.py, runs it (under a query budget) against the visible
# fixture and every hidden fixture, checks the recovered rows up to
# permutation and nonzero per-row scaling, and checks /app/rows.json.
set -u
mkdir -p /logs/verifier
REWARD=0
LOG(){ echo "$*"; }
FAIL=0

[ -f /app/probe_mlp.py ] || { LOG "DELIVERABLE /app/probe_mlp.py missing"; echo 0 > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PY'
import importlib.util
import json
import os
import subprocess
import sys

import numpy as np

failures = []
BUDGET = lambda d, n: 4000 * d + 1000 * n + 10000


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_fixture(path):
    spec = importlib.util.spec_from_file_location("bb_" + str(abs(hash(path))), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.BlackBox()


def check_rows(label, got, exp_rows, tol=1e-3):
    try:
        G = np.asarray(got, dtype=float)
    except Exception as e:
        failures.append("%s: rows not numeric (%r)" % (label, e)); return
    if G.ndim != 2 or G.shape[1] != len(exp_rows[0]):
        failures.append("%s: got shape %r, want (*, %d)" % (label, G.shape, len(exp_rows[0])))
        return
    T = np.asarray(exp_rows, dtype=float)
    if G.shape[0] != T.shape[0]:
        failures.append("%s: got %d rows, want %d" % (label, G.shape[0], T.shape[0]))
        return
    used = [False] * G.shape[0]
    for t in T:
        nt = np.linalg.norm(t)
        if nt < 1e-12:
            failures.append("%s: degenerate expected row" % label); return
        matched = False
        for j in range(G.shape[0]):
            if used[j]:
                continue
            a = G[j]
            na = np.linalg.norm(a)
            if na < 1e-12:
                continue
            denom = float(a @ t)
            if abs(denom) < 1e-12:
                continue
            r = denom / float(t @ t)   # least-squares scale
            resid = np.linalg.norm(a - r * t) / nt
            if resid < tol and abs(r) > 1e-6:
                used[j] = True
                matched = True
                break
        if not matched:
            failures.append("%s: no unused row matches %r" % (label, t.tolist()))
            return


def run_case(label, fixture_path, exp):
    try:
        probe = load_module("probe_mlp_under_test", "/app/probe_mlp.py")
    except Exception as e:
        failures.append("%s: cannot import /app/probe_mlp.py (%r)" % (label, e)); return
    fn = getattr(probe, "extract_rows", None)
    if not callable(fn):
        failures.append("%s: extract_rows missing/not callable" % label); return
    try:
        model = load_fixture(fixture_path)
    except Exception as e:
        failures.append("%s: cannot load fixture (%r)" % (label, e)); return

    in_dim, n_units = exp["in_dim"], exp["n_units"]
    if getattr(model, "in_dim", None) != in_dim or getattr(model, "n_units", None) != n_units:
        failures.append("%s: fixture attrs unexpected" % label); return

    calls = {"n": 0}
    limit = BUDGET(in_dim, n_units)

    def counted_query(x):
        calls["n"] += 1
        if calls["n"] > limit:
            raise RuntimeError("query budget exceeded (%d > %d)" % (calls["n"], limit))
        return model.query(x)

    try:
        got = fn(counted_query, in_dim)
    except Exception as e:
        failures.append("%s: extract_rows raised %r (queries used %d)" % (label, e, calls["n"]))
        return
    check_rows(label, got, exp["rows"])
    print("%s: %d rows, %d/%d queries" % (label, len(got) if hasattr(got, '__len__') else -1,
                                          calls["n"], limit))


# visible fixture
if os.path.isfile("/app/blackbox.py") and os.path.isfile("/tests/expected.json"):
    try:
        exp = json.load(open("/tests/expected.json"))
        run_case("visible", "/app/blackbox.py", exp)
    except Exception as e:
        failures.append("visible case error %r" % e)
else:
    failures.append("visible fixture or /tests/expected.json missing")

# hidden fixtures
hdir = "/tests/hidden"
cases = sorted(os.listdir(hdir)) if os.path.isdir(hdir) else []
if not cases:
    failures.append("no hidden cases present")
for c in cases:
    base = os.path.join(hdir, c)
    fx = os.path.join(base, "blackbox.py")
    expf = os.path.join(base, "expected.json")
    if not (os.path.isfile(fx) and os.path.isfile(expf)):
        failures.append("hidden '%s' malformed fixture" % c); continue
    try:
        exp = json.load(open(expf))
        run_case("hidden-%s" % c, fx, exp)
    except Exception as e:
        failures.append("hidden '%s' error %r" % (c, e))

# rows.json deliverable for the visible fixture
if os.path.isfile("/app/rows.json"):
    try:
        data = json.load(open("/app/rows.json"))
        rows = data.get("rows")
        exp = json.load(open("/tests/expected.json"))
        if not isinstance(rows, list):
            failures.append("rows.json 'rows' is not a list")
        else:
            check_rows("rows.json", rows, exp["rows"])
            if data.get("n_rows") != len(exp["rows"]):
                failures.append("rows.json n_rows mismatch")
    except Exception as e:
        failures.append("rows.json unreadable %r" % e)
else:
    failures.append("missing /app/rows.json")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -ne 0 ]; then FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then
  REWARD=1
  LOG "ALL CHECKS PASS"
fi
echo "$REWARD" > /logs/verifier/reward.txt
exit 0
