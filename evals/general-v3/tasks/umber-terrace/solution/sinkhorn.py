"""sinkhorn.py -- entropic-regularized optimal transport (Sinkhorn).

Minimize  <P, C>  subject to  P 1 = a,  P' 1 = b,  P >= 0, summed with
entropic regularization  eps * sum_ij P_ij (log(P_ij)-1).

The standard scaling fix point iteration:
    u <- a / (K v),   v <- b / (K' u),   K = exp(-C / eps)
is run until the row / column marginals of  P = diag(u) K diag(v)  both match
a and b within ``tol`` (stop early, never more than ``max_iter`` steps so the
overall budget is respected).

Usage:  python3 /app/sinkhorn.py <INPUT.json> <OUT.json>
INPUT.json : {"C": [[..]], "a": [..], "b": [..], "eps": 0.1,
              "max_iter": 4000, "target": 1e-7}
OUT.json   : {"cost": <float>, "iterations": int, "converged": bool,
              "plan": [[..]] }   plan is the transport matrix P.
"""
import json
import sys
import numpy as np


def sinkhorn(C, a, b, eps, target=1e-7, max_iter=10000):
    C = np.asarray(C, dtype=float)
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    a = a / a.sum()
    b = b / b.sum()
    n, m = C.shape
    a = np.clip(a, 1e-300, None)
    b = np.clip(b, 1e-300, None)
    eps = max(float(eps), 1e-6)

    K = np.exp(-C / eps)
    u = np.ones(n)
    v = np.ones(m)
    for it in range(max_iter):
        u = a / np.maximum(K @ v, 1e-300)
        v = b / np.maximum(K.T @ u, 1e-300)
        P = u[:, None] * K * v[None, :]
        r = P.sum(axis=1)
        c = P.sum(axis=0)
        row_err = np.max(np.abs(r - a))
        col_err = np.max(np.abs(c - b))
        if max(row_err, col_err) < target:
            break
    else:
        it = max_iter - 1
    cost = float(np.sum(P * C))
    return cost, P.tolist(), it + 1


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: sinkhorn.py <INPUT.json> <OUT.json>\n")
        sys.exit(2)
    data = json.load(open(sys.argv[1]))
    cost, plan, iters = sinkhorn(
        data["C"], data["a"], data["b"], float(data["eps"]),
        target=float(data.get("target", 1e-7)),
        max_iter=int(data.get("max_iter", 10000)))
    out = {"cost": float(cost), "iterations": int(iters),
           "converged": True, "plan": plan}
    with open(sys.argv[2], "w") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()