#!/bin/bash
set -euo pipefail

# Oracle solution for item-045-main: write /app/probe.py with a robust
# piecewise-linear recovery and validate it on the loaded model.

cat > /app/probe.py <<'PY'
import numpy as np


def _p(model, x):
    return float(model.predict(x))


def _fixed_affines(model, a, b, m=9):
    xs = np.linspace(a, b, m)
    y = np.asarray([_p(model, float(x)) for x in xs])
    A = np.vstack([xs, np.ones_like(xs)]).T
    (slope, inter), _, _, _ = np.linalg.lstsq(A, y, rcond=None)
    return float(slope), float(inter)


def _detect_kinks(model, lo, hi):
    n = 1 << 16
    xs = np.linspace(lo, hi, n)
    y = np.asarray([_p(model, float(x)) for x in xs])
    dx = xs[1] - xs[0]
    slope = np.diff(y) / dx
    dslope = np.diff(slope)
    nz = np.abs(dslope) > 0
    if not np.any(nz):
        return []
    med = np.median(np.abs(dslope[nz]))
    thr = max(3.0 * med, 1e-9)
    cand = np.where(np.abs(dslope) > thr)[0]
    locs = []
    if len(cand):
        splits = np.where(np.diff(cand) > 1)[0] + 1
        for gp in np.split(cand, splits):
            idx = int(gp[0] + len(gp) // 2)
            locs.append(float(xs[min(idx + 1, len(xs) - 1)]))
    return sorted(set(round(k, 10) for k in locs))


def _one_seg(model, a, c):
    s, i = _fixed_affines(model, a, c)
    return {"left": a, "right": c, "slope": s, "intercept": i}


def segment(model, lo, hi):
    kinks = _detect_kinks(model, lo, hi)
    kinks = [k for k in kinks if lo < k < hi]
    allk = [lo] + kinks + [hi]
    segs = []
    for a, c in zip(allk[:-1], allk[1:]):
        if c - a <= 1e-9:
            continue
        segs.append(_one_seg(model, a, c))
    return segs


def evaluate(segs, xs):
    xs = np.atleast_1d(np.asarray(xs, dtype=float))
    out = np.empty_like(xs)
    for s in segs:
        mask = (xs >= s["left"] - 1e-12) & (xs < s["right"])
        out[mask] = s["slope"] * xs[mask] + s["intercept"]
    last = segs[-1]
    sel = xs >= last["right"]
    out[sel] = last["slope"] * xs[sel] + last["intercept"]
    return out
PY

# Self-check on the shipped model.
python3 - <<'PY'
import importlib.util, sys
sys.path.insert(0, "/app")
spec = importlib.util.spec_from_file_location("probe", "/app/probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
import numpy as np
import model
m = model.load_model()
segs = probe.segment(m, -4.0, 4.0)
xs = np.linspace(-4.0, 4.0, 5000)
err = float(np.max(np.abs(np.asarray(m.predict(xs)) - probe.evaluate(segs, xs))))
kinks = [round(s["right"], 3) for s in segs[:-1]]
lines = ["# item-045 recovered piecewise-linear model", ""]
lines.append(f"- segments: {len(segs)}")
lines.append(f"- kinks: {kinks}")
lines.append("- (slope, intercept) per segment:")
for s in segs:
    lines.append(f"  [{s['left']:.3f},{s['right']:.3f}] -> ({s['slope']:.5f}, {s['intercept']:.5f})")
lines.append(f"- max validation error over [-4,4]: {err:.6f}")
lines.append(f"- validation on fresh points: {'PASS' if err < 0.05 else 'FAIL'}")
open("/app/models.md", "w").write("\n".join(lines) + "\n")
assert err < 0.05, f"validation error too large: {err}"
print("oracle self-check passed; segments:", len(segs), "err:", err)
PY