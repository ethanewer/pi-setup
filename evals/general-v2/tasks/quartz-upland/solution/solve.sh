#!/bin/bash
# Quartz Upland oracle: writes the two code deliverables and REGENERATES all
# their outputs by actually running them (never touches /tests).
set -e
cd /app

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""Quartz Upland — climate-finance risk engine (Python 3, numpy only).

Implements: dtype-aware bounded softmax, covariance-weighted risk,
1-D Wasserstein distance with degenerate-case handling, and a
log-concavity-checked rejection sampler. No scipy anywhere.
"""
import json
import math

import numpy as np

_DT = {"float16": np.float16, "float32": np.float32, "float64": np.float64}
_OUT_DT = {"float16": "float16", "float32": "float32",
           "float64": "float64", "mixed": "float32"}
_VALID = ("float16", "float32", "float64", "mixed")


class NonLogConvexError(Exception):
    """Raised when rejection-sampling a non-log-concave target density."""
    pass


# ---------------------------------------------------------------- A1 softmax
def _stable_softmax(arr):
    a = np.asarray(arr, dtype=np.float64)
    a = (a - a.max()).astype(np.float64)
    e = np.exp(a)
    return e / e.sum()


def _softmax_grad(w):
    wd = np.asarray(w, dtype=np.float64).ravel()
    n = wd.size
    G = wd[:, None] * (np.eye(n) - wd[None, :])
    return G.astype(w.dtype)


def softmax_attention(z, dtype):
    if dtype not in _VALID:
        raise ValueError("unsupported dtype tag: %r" % (dtype,))
    if dtype == "mixed":
        # fp16 input consumed by an fp32 model.
        zt = np.asarray(z, dtype=np.float16).astype(np.float32)
    else:
        zt = np.asarray(z, dtype=_DT[dtype])
    outwd = np.asanyarray(zt, dtype=np.float64)
    out = _stable_softmax(outwd).astype(_DT[_OUT_DT[dtype]])
    grad = _softmax_grad(out)
    return out, grad


# ---------------------------------------------------------------- A2 risk
def risk_score(weights, cov):
    w = np.asarray(weights, dtype=np.float64).reshape(-1)
    S = np.asarray(cov, dtype=np.float64)
    if S.ndim != 2 or S.shape[0] != S.shape[1]:
        raise ValueError("covariance must be a square matrix")
    if S.shape[0] != w.size or S.shape[1] != w.size:
        raise ValueError("weight/covariance size mismatch")
    ww = float(w @ w)
    if ww <= 0.0:
        raise ValueError("weight vector has zero norm")
    return float(w @ S @ w) / ww


# ---------------------------------------------------------------- A3 wasserstein
def wasserstein(p, q):
    P = np.asarray(p, dtype=np.float64).reshape(-1)
    Q = np.asarray(q, dtype=np.float64).reshape(-1)
    if P.size == 0 and Q.size == 0:
        return 0.0
    if P.size != Q.size:
        raise ValueError(
            "source/target must carry equal point counts (got %d vs %d)"
            % (P.size, Q.size))
    return float(np.mean(np.abs(np.sort(P) - np.sort(Q))))


# ---------------------------------------------------------------- A4 sampler
def _grid(bounds):
    lo, hi = float(bounds[0]), float(bounds[1])
    if not (np.isfinite(lo) and np.isfinite(hi)) or lo >= hi:
        raise ValueError("invalid bounds: %r" % (tuple(bounds),))
    return lo, hi, np.linspace(lo, hi, 41)


def sample_density(logp, count, bounds):
    if not callable(logp):
        raise TypeError("logp must be callable")
    if not isinstance(count, (int, np.integer)) or count <= 0:
        raise ValueError("count must be a positive integer")
    lo, hi, grid = _grid(bounds)

    vals = np.array([float(logp(float(gx))) for gx in grid], dtype=np.float64)
    if not np.all(np.isfinite(vals)):
        raise ValueError("log-density returned non-finite values")

    # Deterministic finite log-concavity probe (midpoint inequality).
    for i in range(grid.size):
        for j in range(i + 2, grid.size):
            mid = 0.5 * (grid[i] + grid[j])
            lhs = float(logp(float(mid)))
            rhs = 0.5 * (float(vals[i]) + float(vals[j]))
            if lhs < rhs - 1e-7:
                raise NonLogConvexError(
                    "target not log-concave (midpoint violation %.4g/%.4g)"
                    % (grid[i], grid[j]))

    lmax = float(vals.max())
    rng = np.random.default_rng(20240517)
    samp = []
    budget = count * 400000 + 4000
    tries = 0
    while len(samp) < count and tries < budget:
        tries += 1
        x = rng.uniform(lo, hi)
        u = float(rng.uniform())
        if math.log(u) < float(logp(float(x))) - lmax:
            samp.append(x)
    if len(samp) < count:
        raise RuntimeError("rejection sampler exhausted budget")
    return np.asarray(samp, dtype=np.float64)


# ---------------------------------------------------------------- __main__
def _default_logp(x):
    x = np.float64(x)
    return -0.5 * ((x - 0.25) / 1.2) ** 2.0


if __name__ == "__main__":
    with open("/app/input_data.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    att, _g = softmax_attention(data["attn_z"], data.get("attn_dtype", "float64"))
    s = sample_density(_default_logp, 96, data["sample_bounds"])
    answer = {
        "risk_score": risk_score(data["risk_weights"], data["risk_cov"]),
        "wasserstein": wasserstein(data["dist_p"], data["dist_q"]),
        "attention_sum": float(np.sum(att, dtype=np.float64)),
        "attention_dtype": _OUT_DT[data.get("attn_dtype", "float64")],
        "sample_mean": float(np.mean(s)),
        "sample_std": float(np.std(s)),
        "sample_count": int(s.size),
        "sample_within": bool(np.all(np.isfinite(s))),
    }
    with open("/app/answer.json", "w", encoding="utf-8") as f:
        json.dump(answer, f, indent=2)
PYEOF

cat > /app/reporting_converted.py <<'PYEOF'
#!/usr/bin/env python3
"""Python 3 port of reporting_legacy.py using pathlib/configparser/pandas."""
import configparser
from pathlib import Path

import pandas as pd

ROOT = Path("/app")

cfg = configparser.ConfigParser()
cfg.read(ROOT / "cascade_config.ini", encoding="utf-8")
csv_path = Path(cfg.get("report", "csv_path"))
start_year = cfg.getint("report", "start_year")
out_path = Path(cfg.get("report", "out_path"))

df = pd.read_csv(csv_path, encoding="utf-8")
df = df[df["year"] >= start_year]
grouped = df.groupby("year")["maxtemp"].mean().reset_index()
grouped.columns = ["year", "mean_maxtemp"]
grouped.to_csv(out_path, index=False, encoding="utf-8")

print(f"converted {len(df)} rows into {out_path}")
PYEOF

chmod +x /app/solve.py /app/reporting_converted.py

python3 /app/reporting_converted.py
python3 /app/solve.py

echo "oracle done"