#!/bin/bash
# Verifier for quartz-delta (executes-deliverable).
# Imports /app/kernels.py and checks each public function against an independent
# numpy/scipy reference on both the visible fixture and fresh hidden inputs.
# Deterministic, no network. Never reuses the oracle implementation.
set -euo pipefail

mkdir -p /logs/verifier
cd /app

# The if-guards wrap the checks so a failing check still lets us write the reward file.
if ! python3 - <<'PY'
import numpy as np
import importlib.util
import os
from scipy.optimize import linprog
from scipy.spatial.distance import cdist


def err(msg):
    raise SystemExit("FAIL: " + msg)


def pts(x):
    x = np.asarray(x, float)
    return x if x.ndim == 2 else x.reshape(-1, 1)


def gold_emd(a, b):
    """Independent reference: exact 1-Wasserstein via LP optimum."""
    a, b = pts(a), pts(b)
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        raise ValueError("empty")
    if np.array_equal(a, b):
        return 0.0
    if n == 1 and m == 1:
        return float(np.linalg.norm(a[0] - b[0]))
    C = cdist(a, b)
    A = np.zeros((n + m, n * m))
    be = np.zeros(n + m)
    for i in range(n):
        A[i, i * m:(i + 1) * m] = 1.0
        be[i] = 1.0 / n
    for j in range(m):
        A[n + j, j::m] = 1.0
        be[n + j] = 1.0 / m
    r = linprog(C.ravel(), A_eq=A, b_eq=be, bounds=(0, None), method="highs")
    if not r.success:
        raise RuntimeError("lp failed")
    return float(r.fun)


# ---- 0) load the deliverable ----
if not os.path.exists("/app/kernels.py"):
    err("missing /app/kernels.py")
spec = importlib.util.spec_from_file_location("kernels", "/app/kernels.py")
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)

for fn in ("compute_wasserstein_distance", "compute_wasserstein_grid",
           "reconstruct_eigenvector_components", "ode_solve_landing"):
    if not callable(getattr(k, fn, None)):
        err("missing public function %s" % fn)

# ---- 1) out.npy deliverable: eigen reconstruction of the fixture ----
if not os.path.exists("/app/fixture.npy"):
    err("fixture missing")
if not os.path.exists("/app/out.npy"):
    err("missing /app/out.npy")
F = np.load("/app/fixture.npy")
want = k.reconstruct_eigenvector_components(F)
got = np.load("/app/out.npy")
if got.shape != want.shape or not np.allclose(got, want, atol=1e-7, rtol=1e-7):
    err("out.npy does not match reconstruction of fixture")

# ---- 2) exact Wasserstein on hidden datasets vs independent gold ----
for nm in ("cluster", "thin", "oned", "sep"):
    a = pts(np.load("/tests/hidden/wasser/a_%s.npy" % nm))
    b = pts(np.load("/tests/hidden/wasser/b_%s.npy" % nm))
    g = gold_emd(a, b)
    r = k.compute_wasserstein_distance(a, b, method="exact")
    if abs(r - g) > 1e-5 * max(g, 1e-9):
        err("exact diverges on %s" % nm)

# ---- 3) grid path within error band + dispatch ----
for name in ("cluster", "thin", "oned", "sep"):
    a = pts(np.load("/tests/hidden/wasser/a_%s.npy" % name))
    b = pts(np.load("/tests/hidden/wasser/b_%s.npy" % name))
    g = gold_emd(a, b)
    gr = k.compute_wasserstein_grid(a, b, bins=24)
    if abs(gr - g) > 0.20 * max(g, 1e-9) + 0.05:
        err("grid out of band on %s" % name)
    dg = k.compute_wasserstein_distance(a, b, method="grid", bins=24)
    if abs(dg - gr) > 1e-9:
        err("grid dispatch mismatch on %s" % name)

# ---- 4) degenerate / edge / symmetry across both methods ----
base = np.array([[0.0, 0.0], [1.0, 1.0], [2.0, 0.0]])
if abs(k.compute_wasserstein_distance(base, base, method="exact")) > 1e-9:
    err("identical clouds not 0 (exact)")
if abs(k.compute_wasserstein_distance(base, base, method="grid")) > 1e-9:
    err("identical clouds not 0 (grid)")
for meth in ("exact", "grid"):
    try:
        k.compute_wasserstein_distance(np.zeros((0, 2)), base, method=meth)
        err("empty cloud did not raise (" + meth + ")")
    except ValueError:
        pass
    try:
        k.compute_wasserstein_grid(np.zeros((0, 2)), base)
        err("empty cloud did not raise (grid fn)")
    except ValueError:
        pass
sp1 = np.array([[0.0, 0.0]])
sp2 = np.array([[3.0, 4.0]])
if abs(k.compute_wasserstein_distance(sp1, sp2, method="exact") - 5.0) > 1e-9:
    err("single-point exact not euclidean")
if abs(k.compute_wasserstein_distance(sp1, sp2, method="grid") - 5.0) > 1e-9:
    err("single-point grid not euclidean")
swap = np.array([[5.0, 5.0], [6.0, 6.0], [7.0, 5.0]])
r_ab = k.compute_wasserstein_distance(base, swap, method="exact")
r_ba = k.compute_wasserstein_distance(swap, base, method="exact")
if abs(r_ab - r_ba) > 1e-9:
    err("exact distance not symmetric under swap")

# ---- 5) eigen reconstruction on hidden symmetric matrix ----
A6 = np.load("/tests/hidden/eigen/A6.npy")
re = k.reconstruct_eigenvector_components(A6)
w, V = np.linalg.eigh(A6)
if not np.allclose(np.abs(V), re, atol=1e-6, rtol=1e-6):
    err("eigen reconstruction off hidden matrix")

# ---- 6) ODE landing on hidden eval times ----
et = np.load("/tests/hidden/ode/eval_times.npy")
rhs = lambda t, y: np.array([-y[0]])
res = k.ode_solve_landing(rhs, 0.0, 1.0, et, [1.0], step=0.05)
ev = np.asarray(res["eval_times"], float)
yv = np.asarray(res["y"])
rts = np.asarray(res["rhs_times"], float)
for et_ in et:
    i = int(np.argmin(np.abs(ev - float(et_))))
    ref = float(np.exp(-float(et_)))
    if abs(float(yv[i][0]) - ref) > 2e-3 * ref:
        err("ODE landing value off at %s" % (et_,))
    if not np.any(np.abs(rts - float(et_)) < 1e-8):
        err("no exact rhs call at %s" % (et_,))
    prior = [float(s) for s in rts if float(s) < float(et_) - 1e-8]
    if not prior or (float(et_) - max(prior)) > 0.06:
        err("no short preceding rhs gap before %s" % (et_,))

print("ALL OK")
PY
then
    echo "python gold check failed"
    echo "REWARD=0"
    echo "0" > /logs/verifier/reward.txt
    exit 1
fi

reward=1
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt