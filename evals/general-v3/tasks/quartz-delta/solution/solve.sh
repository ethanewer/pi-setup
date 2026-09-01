#!/bin/bash
# Oracle for quartz-delta. Writes the deliverable /app/kernels.py (by hand, doing the
# real numerical-kernel work), then RUNS it on the shipped fixture to produce
# /app/out.npy. Never reads /tests and never cats a precomputed hidden answer.
set -eu

cat > /app/kernels.py <<'PY'
#!/usr/bin/env python3
"""quartz-delta: numerical kernels library.

Public API:
    compute_wasserstein_distance(a, b, method="exact", bins=24) -> float
    compute_wasserstein_grid(a, b, bins=24) -> float
    reconstruct_eigenvector_components(A) -> np.ndarray  (n, n) of magnitudes
    ode_solve_landing(rhs, t0, t_end, eval_times, y0, step=0.05) -> dict
"""
import numpy as np
from scipy.spatial.distance import cdist
from scipy.optimize import linprog


def _as_points(x):
    x = np.asarray(x, dtype=float)
    return x if x.ndim == 2 else x.reshape(-1, 1)


def _emd(a, b):
    """Exact 1-Wasserstein (Earth-Mover) cost between two empirical measures."""
    a, b = _as_points(a), _as_points(b)
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        raise ValueError("empty point set")
    if np.array_equal(a, b):
        return 0.0
    if n == 1 and m == 1:
        return float(np.linalg.norm(a[0] - b[0]))
    C = cdist(a, b)
    A = np.zeros((n + m, n * m))
    be = np.zeros(n + m)
    for i in range(n):
        A[i, i*m:(i + 1)*m] = 1.0
        be[i] = 1.0 / n
    for j in range(m):
        A[n + j, j::m] = 1.0
        be[n + j] = 1.0 / m
    res = linprog(C.ravel(), A_eq=A, b_eq=be, bounds=(0, None), method="highs")
    if not res.success:
        raise RuntimeError("transport LP did not converge")
    return float(res.fun)


def compute_wasserstein_grid(a, b, bins=24):
    """Grid-approximated 1-Wasserstein via histograms + entropic (Sinkhorn) coupling."""
    a, b = _as_points(a), _as_points(b)
    if len(a) == 0 or len(b) == 0:
        raise ValueError("empty point set")
    if np.array_equal(a, b):
        return 0.0
    if len(a) == 1 and len(b) == 1:
        return float(np.linalg.norm(a[0] - b[0]))
    allp = np.vstack([a, b])
    d = allp.shape[1]
    lo = allp.min(axis=0)
    hi = allp.max(axis=0)
    pad = (hi - lo) * 0.05 + 1e-6
    lo = lo - pad
    hi = hi + pad
    edges = [np.linspace(lo[k], hi[k], bins + 1) for k in range(d)]
    centers = [(edges[k][1:] + edges[k][:-1]) / 2 for k in range(d)]
    mesh = np.meshgrid(*centers, indexing="ij")
    cells = np.stack([m.ravel() for m in mesh], axis=1)

    def _hist_idx(pts):
        idx = np.clip(np.digitize(pts[:, 0], edges[0]) - 1, 0, bins - 1)
        for k in range(1, d):
            idx = idx * bins + np.clip(np.digitize(pts[:, k], edges[k]) - 1, 0, bins - 1)
        return idx.astype(np.intp)

    idxa = _hist_idx(a)
    idxb = _hist_idx(b)
    ra = np.bincount(idxa, minlength=len(cells)).astype(float) / len(a)
    rb = np.bincount(idxb, minlength=len(cells)).astype(float) / len(b)
    # Only cells that carry at least one atom of mass participate in transport;
    # cells with zero supply AND zero demand contribute exactly zero cost, so
    # restricting to the occupied cells keeps the grid result identical while
    # bounding memory (avoids a full bins**d x bins**d coupling matrix).
    occ = np.unique(np.concatenate([idxa, idxb]))
    ra = ra[occ]
    rb = rb[occ]
    cells = cells[occ]
    C = cdist(cells, cells)
    eps = 0.1 * np.median(C[C > 0.0]) if np.any(C > 0.0) else 1.0
    K = np.exp(-C / eps)
    u = np.ones(len(cells))
    v = np.ones(len(cells))
    for _ in range(200):
        u = ra / (K @ v + 1e-300)
        u = np.clip(u, None, 1e12)
        v = rb / (K.T @ u + 1e-300)
        v = np.clip(v, None, 1e12)
    T = u[:, None] * K * v[None, :]
    return float(np.sum(T * C))


def compute_wasserstein_distance(a, b, method="exact", bins=24):
    """Main interface. method="exact" -> LP optimum; method="grid" -> gridded Sinkhorn."""
    a, b = _as_points(a), _as_points(b)
    if len(a) == 0 or len(b) == 0:
        raise ValueError("empty point set")
    if method == "grid":
        return compute_wasserstein_grid(a, b, bins=bins)
    if method == "exact":
        return _emd(a, b)
    raise ValueError("unknown method: %r" % (method,))


def reconstruct_eigenvector_components(A):
    """Absolute values of the orthonormal eigenvectors, columns ascending by eigenvalue.

    Paper-style reconstruction from the spectrum and the matrix: for each distinct
    eigenvalue lambda_k the scaled spectral projector
        P_k = prod_{j!=k}(A - lambda_j I) / prod_{j!=k}(lambda_k - lambda_j) = v_k v_k^T,
    so |v_{i,k}| = sqrt( P_k[i, i] ). Columns normalised to unit norm and ordered by
    ascending eigenvalue (matching numpy.linalg.eigh column order).
    """
    A = np.asarray(A, dtype=float)
    if A.ndim != 2 or A.shape[0] != A.shape[1]:
        raise ValueError("A must be a square matrix")
    if not np.allclose(A, A.T):
        raise ValueError("A must be symmetric")
    n = A.shape[0]
    w = np.linalg.eigvalsh(A)          # spectrum, ascending
    I = np.eye(n)
    out = np.zeros((n, n))
    for k in range(n):
        P = np.eye(n)
        den = 1.0
        for j in range(n):
            if j != k:
                P = P @ (A - w[j] * I)
                den *= (w[k] - w[j])
        P = P / den
        diag = np.clip(np.diag(P).real, 0.0, None)
        col = np.sqrt(diag)
        nrm = np.linalg.norm(col)
        out[:, k] = col / nrm if nrm > 0 else col
    return out


def ode_solve_landing(rhs, t0, t_end, eval_times, y0, step=0.05):
    """Integrate dy/dt = rhs(t, y) from t0 to t_end landing exactly at each eval_t.

    No interpolation for outputs: the substep reaching each output time is clamped so
    the right-hand side is evaluated exactly at that time. Returns a dict with
    eval_times, y (values at the eval times), and rhs_times (every rhs call time).
    """
    ev = np.asarray(sorted(set(float(x) for x in eval_times)), dtype=float)
    ev = ev[(ev >= t0 - 1e-9) & (ev <= t_end + 1e-9)]
    if len(ev) == 0:
        raise ValueError("no eval_times within [t0, t_end]")
    y = np.array(y0, dtype=float).reshape(-1)
    t = float(t0)
    rhs_times = [t]
    targets = np.unique(np.r_[ev, t_end])
    targets = targets[targets > t0 - 1e-12]
    ti = 0
    visited = {t: y.copy()}

    def _rk4(t, y, h):
        k1 = np.array(rhs(t, y), dtype=float)
        k2 = np.array(rhs(t + 0.5 * h, y + 0.5 * h * k1), dtype=float)
        rhs_times.append(t + 0.5 * h)
        k3 = np.array(rhs(t + 0.5 * h, y + 0.5 * h * k2), dtype=float)
        rhs_times.append(t + 0.5 * h)
        k4 = np.array(rhs(t + h, y + h * k3), dtype=float)
        rhs_times.append(t + h)
        return t + h, y + h * (k1 + 2 * k2 + 2 * k3 + k4) / 6.0

    while t < t_end - 1e-12:
        nt = targets[ti]
        while nt <= t + 1e-12:
            ti += 1
            nt = targets[ti]
        h = min(step, max(1e-14, nt - t))
        t, y = _rk4(t, y, h)
        visited[t] = y.copy()

    yev = np.array([visited[round(float(x), 12)] for x in ev])
    return dict(eval_times=ev, y=yev,
                rhs_times=np.array(rhs_times, dtype=float))
PY
chmod +x /app/kernels.py

# Produce the visible-case deliverable by actually RUNNING the kernel library.
python3 - <<'PY'
import numpy as np
import kernels
A = np.load("/app/fixture.npy")
np.save("/app/out.npy", kernels.reconstruct_eigenvector_components(A))
print("out.npy shape:", np.load("/app/out.npy").shape)
PY

echo "oracle produced /app/kernels.py and /app/out.npy"