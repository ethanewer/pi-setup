"""quartic_min.py -- minimize a composite smooth objective over a vector x.

f(x) = sum_i  p_i * (x_i - u_i)^4
     + sum_g  a_g * || x[group_g] - m_g ||^2      (per-vector quadratic penalty)
     + 0.5 * x' Q x                                 (global quadratic coupling)
     + l' x

The instance JSON supplies p, u, groups, m, a, Q, l and a dimension n.  The
problem is run to a near-stationary point (small gradient norm); because every
term is (individually) convex, gradient strategies converge to the global min.

Usage:  python3 /app/quartic_min.py <INPUT.json> <OUTPUT.json>
OUTPUT.json: {"x": [..], "objective": <float>, "grad_norm": <float>}
"""
import json
import sys
import numpy as np
from scipy.optimize import minimize


def build_terms(data):
    n = int(data["n"])
    p = np.asarray(data["p"], dtype=float)
    u = np.asarray(data["u"], dtype=float)
    l = np.asarray(data.get("l", np.zeros(n)), dtype=float)
    Q = np.asarray(data["Q"], dtype=float)
    groups = [list(g) for g in data["groups"]]
    agg = {tuple(g): idx for idx, g in enumerate(groups)}
    a = np.asarray(data["a"], dtype=float)
    m = [np.asarray(mm, dtype=float) for mm in data["m"]]
    return n, u, p, l, Q, groups, a, m


def objective_and_grad(x, u, p, l, Q, groups, a, m):
    x = np.asarray(x, dtype=float)
    q = p * ((x - u) ** 4)
    f = float(np.sum(q) + np.dot(l, x) + 0.5 * np.dot(x, Q.dot(x)))
    g = 4 * p * ((x - u) ** 3) + l + Q.dot(x)
    for gi, idxs in enumerate(groups):
        g_idx = np.asarray(idxs, dtype=int)
        g_center = m[gi]
        diff = x[g_idx] - g_center
        f += float(a[gi]) * np.sum(diff * diff)
        g[g_idx] += 2 * float(a[gi]) * diff
    return f, g


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: quartic_min.py <INPUT.json> <OUT.json>\n")
        sys.exit(2)
    data = json.load(open(sys.argv[1]))
    n, u, p, l, Q, groups, a, m = build_terms(data)

    rng = np.random.default_rng(data.get("seed", 0))
    x0 = u + rng.normal(0.0, 0.5, n)

    def fg(xt):
        return objective_and_grad(xt, u, p, l, Q, groups, a, m)

    res = minimize(fg, x0, jac=True, method="L-BFGS-B",
                   options={"maxiter": 800, "ftol": 1e-14, "gtol": 1e-9})
    xstar = np.clip(res.x, -1e6, 1e6)
    fstar, gstar = objective_and_grad(xstar, u, p, l, Q, groups, a, m)
    grad = float(np.linalg.norm(gstar))

    # a light multi-start to shake free of any shallow traps
    for _ in range(3):
        x2 = u + rng.normal(0.0, 0.8, n)
        r2 = minimize(fg, x2, jac=True, method="L-BFGS-B",
                      options={"maxiter": 600, "ftol": 1e-13, "gtol": 1e-8})
        x2s = np.clip(r2.x, -1e6, 1e6)
        f2, _ = objective_and_grad(x2s, u, p, l, Q, groups, a, m)
        if f2 < fstar - 1e-9:
            fstar, xstar, grad = f2, x2s, float(np.linalg.norm(
                objective_and_grad(x2s, u, p, l, Q, groups, a, m)[1]))

    with open(sys.argv[2], "w") as fh:
        json.dump({"solution": [round(float(v), 10) for v in xstar],
                   "objective": float(fstar),
                   "grad_norm": grad}, fh, indent=2)


if __name__ == "__main__":
    main()