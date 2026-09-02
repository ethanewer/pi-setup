#!/usr/bin/env python3
"""Independent reference verifier for task id=umber-terrace.

Runs the four /app deliverable programs on the hidden inputs under
/tests/hidden and compares their outputs / solves the same problems with an
independent solver (pulp/CBC for MIP, its own enumeration for corners, scipy
for the quartic objective and its own Sinkhorn scaling for OT).

Exits 0 only when every sub-test passes; otherwise 1.  The caller
(tests/test.sh) translates the exit code into the numeric reward.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

import numpy as np
from scipy.optimize import minimize
import pulp

APP = "/app"
HIDDEN = "/tests/hidden"

fails = []
passes = []
def ok(name):
    passes.append(name); print(f"PASS  {name}", flush=True)
def bad(name, why):
    fails.append(name); print(f"FAIL  {name}: {why}", flush=True)

def run(prog, *args, timeout=60):
    cmd = [sys.executable, os.path.join(APP, prog)] + list(args)
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    dt = time.time() - t0
    return r, dt

# ---------------------------------------------------------------- deliverables
DELIVERABLES = [
    "/app/solve_mip.py", "/app/mip_result.json", "/app/corners.py", "/app/corners.txt",
    "/app/quartic_min.py", "/app/quartic_solution.json", "/app/sinkhorn.py", "/app/ot_cost.json",
]
missing = [p for p in DELIVERABLES if not os.path.isfile(p)]
if missing:
    print("MISSING deliverables:", missing, flush=True)
    print("VERDICT 0", flush=True)
    sys.exit(1)   # non-zero so the caller writes reward 0

# ------------------------------------------------ 1. mixed-integer programming
mip_files = sorted(x for x in os.listdir(os.path.join(HIDDEN, "mip"))
                   if x.endswith(".mps"))
for f in mip_files:
    path = os.path.join(HIDDEN, "mip", f)
    out = f"/tmp/agent_{f}.json"
    r, dt = run("solve_mip.py", path, out, timeout=120)
    if r.returncode != 0:
        bad(f"mip[{f}]", f"agent script rc={r.returncode} {r.stderr[-300:]}")
        continue
    try:
        agent = json.load(open(out))
    except Exception as e:
        bad(f"mip[{f}]", f"unparseable agent output: {e}")
        continue
    vars_, prob = pulp.LpProblem.fromMPS(path)
    sol = pulp.PULP_CBC_CMD(msg=False)
    prob.solve(sol)
    if pulp.LpStatus[prob.status] != "Optimal":
        bad(f"mip[{f}]", "reference CBC not optimal")
        continue
    ref_obj = pulp.value(prob.objective)
    ref_vals = {v.name: v.value() for v in prob.variables()}
    if not agent.get("optimal"):
        bad(f"mip[{f}]", f"agent reports optimal=False status={agent.get('status')}")
        continue
    aobj = agent.get("objective")
    if aobj is None:
        bad(f"mip[{f}]", "no objective in agent output"); continue
    if abs(aobj - ref_obj) > 1e-4 + 1e-9 * abs(ref_obj):
        bad(f"mip[{f}]", f"objective {aobj:.6f} != ref {ref_obj:.6f}"); continue
    # variable values need to match on the names that exist in both
    ax = agent.get("x", {})
    worst = 0.0
    for vname, rv in ref_vals.items():
        if vname in ax:
            worst = max(worst, abs(rv - ax[vname]))
        else:
            bad(f"mip[{f}]", f"agent missing var {vname}"); break
    else:
        if worst > 1e-2:
            bad(f"mip[{f}]", f"variable values diverge (worst {worst:.4f})")
        else:
            ok(f"mip[{f}] (obj {aobj:.5f}, {dt:.1f}s)")

# ---------------------------------------------------------------- 2. corners
def read_corners(path):
    with open(path) as fh:
        lines = [ln for ln in fh.read().splitlines() if ln.strip()]
    k = int(lines[0].strip())
    pts = set()
    for ln in lines[1:]:
        pts.add(tuple(round(float(x), 5) for x in ln.split()))
    return k, pts

def expected_corners(data):
    A = np.asarray(data["A"], float); b = np.asarray(data["b"]).reshape(-1)
    m, n = A.shape
    import itertools
    out = set()
    for cols in itertools.combinations(range(n), m):
        B = A[:, list(cols)]
        try:
            xB = np.linalg.solve(B, b)
        except np.linalg.LinAlgError:
            continue
        if np.any(xB < -1e-9):
            continue
        full = np.zeros(n); full[list(cols)] = xB
        out.add(tuple(round(float(v), 5) for v in full))
    return out

for f in sorted(os.listdir(os.path.join(HIDDEN, "corners"))):
    if not f.endswith(".json"):
        continue
    path = os.path.join(HIDDEN, "corners", f)
    out = f"/tmp/agent_{f}.txt"
    r, dt = run("corners.py", path, out, timeout=60)
    if r.returncode != 0:
        bad(f"corners[{f}]", r.stderr[-300:]); continue
    data = json.load(open(path))
    ref = expected_corners(data)   # independent enumeration
    try:
        _cnt, agent_c = read_corners(out)
    except Exception as e:
        bad(f"corners[{f}]", f"bad output: {e}"); continue
    if agent_c != ref:
        bad(f"corners[{f}]", f"corner set mismatch agent#={len(agent_c)} ref#={len(ref)}")
    else:
        ok(f"corners[{f}] (count={len(ref)}, {dt:.2f}s)")

# --------------------------------------------- 3. quartic objective
def qbuild(data):
    n = int(data["n"]); u = np.array(data["u"]); p = np.array(data["p"])
    Q = np.array(data["Q"]); l = np.array(data.get("l", np.zeros(n)))
    groups = [list(g) for g in data["groups"]]
    a = np.array(data["a"]); m = [np.array(mm) for mm in data["m"]]
    return n, u, p, Q, l, groups, a, m

def fg(x, data, ntu=None):
    _n, u, p, Q, l, groups, a, m = ntu
    x = np.asarray(x, float)
    val = float(np.sum(p * (x - u) ** 4) + np.dot(l, x) + 0.5 * np.dot(x, Q.dot(x)))
    g = 4 * p * (x - u) ** 3 + l + Q.dot(x)
    for gi, idxs in enumerate(groups):
        idx = np.array(idxs, int)
        diff = x[idx] - m[gi]
        val += float(a[gi]) * np.sum(diff * diff)
        g[idx] += 2 * float(a[gi]) * diff
    return val, g

for f in sorted(os.listdir(os.path.join(HIDDEN, "quartic"))):
    if not f.endswith(".json"):
        continue
    path = os.path.join(HIDDEN, "quartic", f)
    out = f"/tmp/agent_{f}.json"
    r, dt = run("quartic_min.py", path, out, timeout=180)
    if r.returncode != 0:
        bad(f"quartic[{f}]", r.stderr[-300:]); continue
    try:
        agent = json.load(open(out))
    except Exception as e:
        bad(f"quartic[{f}]", f"unparseable: {e}"); continue
    data = json.load(open(path))
    ntu = qbuild(data)
    # reference minimizer
    u0 = ntu[1]
    best = minimize(lambda x: fg(x, data, ntu), u0, jac=True, method="L-BFGS-B",
                    options={"maxiter": 2000, "gtol": 1e-10})
    ref_obj, _ = fg(best.x, data, ntu)
    aobj = float(agent.get("objective"))
    if aobj is None or aobj > 1e8 or aobj < -1e8:
        bad(f"quartic[{f}]", f"objective out of range: {aobj}"); continue
    if abs(aobj - ref_obj) > 5e-2 + 1e-4 * abs(ref_obj):
        bad(f"quartic[{f}]", f"objective {aobj:.5f} != ref {ref_obj:.5f}"); continue
    ag = float(agent.get("grad_norm", 1e9))
    if ag > 0.5:
        bad(f"quartic[{f}]", f"not near-stationary (grad_norm={ag})"); continue
    # consistency: verifier re-evaluates agent's reported point against the SAME model
    xs = np.array(agent.get("solution", []), float)
    if xs.size != ntu[0]:
        bad(f"quartic[{f}]", f"solution length {xs.size} != n"); continue
    rep_obj, _ = fg(xs, data, ntu)
    if abs(rep_obj - aobj) > 1e-3 + 1e-6 * abs(aobj):
        bad(f"quartic[{f}]", f"reported objective inconsistent with point"); continue
    ok(f"quartic[{f}] (obj={aobj:.4f}, grad={ag:.1e}, {dt:.1f}s)")

# --------------------------------------------- 4. sinkhorn OT
def sinkhorn_ref(C, a, b, eps, target=1e-9, max_iter=40000):
    C = np.asarray(C, float); a = np.asarray(a, float); b = np.asarray(b, float)
    a = a / a.sum(); b = b / b.sum()
    a = np.clip(a, 1e-300, None); b = np.clip(b, 1e-300, None)
    K = np.exp(-C / max(eps, 1e-6))
    u = np.ones(C.shape[0]); v = np.ones(C.shape[1])
    for _ in range(max_iter):
        u = a / np.maximum(K @ v, 1e-300)
        v = b / np.maximum(K.T @ u, 1e-300)
        P = u[:, None] * K * v[None, :]
        if max(np.max(np.abs(P.sum(1) - a)), np.max(np.abs(P.sum(0) - b))) < target:
            break
    return float(np.sum(P * C)), P

for f in sorted(os.listdir(os.path.join(HIDDEN, "sinkhorn"))):
    if not f.endswith(".json"):
        continue
    path = os.path.join(HIDDEN, "sinkhorn", f)
    out = f"/tmp/agent_{f}.json"
    r, dt = run("sinkhorn.py", path, out, timeout=120)
    if r.returncode != 0:
        bad(f"sinkhorn[{f}]", r.stderr[-300:]); continue
    try:
        agent = json.load(open(out))
    except Exception as e:
        bad(f"sinkhorn[{f}]", f"unparseable: {e}"); continue
    data = json.load(open(path))
    acost = float(agent.get("cost"))
    ref_cost, refP = sinkhorn_ref(data["C"], data["a"], data["b"], float(data["eps"]),
                                  float(data.get("target", 1e-9)))
    if not np.isfinite(acost) or abs(acost - ref_cost) > 1e-4 + 1e-3 * abs(ref_cost):
        bad(f"sinkhorn[{f}]", f"cost {acost:.6f} != ref {ref_cost:.6f}"); continue
    P_agent = agent.get("plan")
    if P_agent is None:
        bad(f"sinkhorn[{f}]", "no plan"); continue
    Pa = np.asarray(P_agent, float)
    a = np.asarray(data["a"], float); a = a / a.sum()
    b = np.asarray(data["b"], float); b = b / b.sum()
    row_e = np.max(np.abs(Pa.sum(1) - a))
    col_e = np.max(np.abs(Pa.sum(0) - b))
    if max(row_e, col_e) > 1e-3:
        bad(f"sinkhorn[{f}]", f"wrong marginals rowerr={row_e:.1e} colerr={col_e:.1e}"); continue
    if dt > 90:
        bad(f"sinkhorn[{f}]", f"exceeded per-run budget ({dt:.1f}s)")
    else:
        ok(f"sinkhorn[{f}] (cost={acost:.5f}, {dt:.1f}s)")

print("-" * 40)
print(f"passed={len(passes)} failed={len(fails)}")
sys.exit(0 if not fails else 1)