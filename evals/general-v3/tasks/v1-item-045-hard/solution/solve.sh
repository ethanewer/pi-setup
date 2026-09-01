#!/bin/bash
set -euo pipefail

cat > /app/probe.py <<'PY'
import numpy as np


def _p(model, x):
    return float(model.predict(x))


def _fit_line(model, a, b, m=11):
    xs = np.linspace(a, b, m)
    y = np.asarray([_p(model, float(x)) for x in xs])
    A = np.vstack([xs, np.ones_like(xs)]).T
    (slope, inter), _, _, _ = np.linalg.lstsq(A, y, rcond=None)
    return float(slope), float(inter)


def _detect_kinks(model, lo, hi, grid_exp=17):
    n = 1 << grid_exp
    xs = np.linspace(lo, hi, n)
    y = np.asarray([_p(model, float(x)) for x in xs])
    dx = xs[1] - xs[0]
    slope = np.diff(y) / dx
    dslope = np.diff(slope)
    nz = np.abs(dslope) > 0
    if not np.any(nz):
        return []
    med = np.median(np.abs(dslope[nz]))
    thr = max(2.2 * med, 1e-9)
    cand = np.where(np.abs(dslope) > thr)[0]
    locs = []
    if len(cand):
        splits = np.where(np.diff(cand) > 1)[0] + 1
        for gp in np.split(cand, splits):
            idx = int(gp[0] + len(gp) // 2)
            locs.append(float(xs[min(idx + 1, len(xs) - 1)]))
    return sorted(set(round(k, 10) for k in locs))


def _refine(model, raw, lo, hi):
    frontier = [lo] + raw + [hi]
    refined = []
    for i in range(1, len(frontier) - 1):
        k = frontier[i]
        a = frontier[i - 1]
        b = frontier[i + 1]
        d = max(0.003, (k - a) * 0.18, (b - k) * 0.18)
        if (k - d) - (a + d) <= 1e-9 or (b - d) <= (k + d) - 1e-9:
            refined.append(k)
            continue
        sl, il = _fit_line(model, a + d, k - d)
        sr, ir = _fit_line(model, k + d, b - d)
        denom = sl - sr
        if abs(denom) < 1e-12:
            refined.append(k)
        else:
            xk = (ir - il) / denom
            refined.append(xk if abs(xk - k) < 0.05 else k)
    return sorted(set(round(v, 8) for v in refined))


def segment(model, lo, hi):
    raw = _detect_kinks(model, lo, hi)
    raw = [k for k in raw if lo < k < hi]
    kinks = _refine(model, raw, lo, hi) if raw else []
    kinks = [k for k in kinks if lo + 1e-9 < k < hi - 1e-9]
    allk = [lo] + kinks + [hi]
    segs = []
    for aa, cc in zip(allk[:-1], allk[1:]):
        if cc - aa <= 1e-9:
            continue
        sl, ic = _fit_line(model, aa, cc)
        segs.append({"left": aa, "right": cc, "slope": sl, "intercept": ic})
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

python3 - <<'PY'
import importlib.util, sys, json
sys.path.insert(0, "/app")
spec = importlib.util.spec_from_file_location("probe", "/app/probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
import numpy as np
import model
m = model.load_model()
lo, hi = -6.0, 6.0
segs = probe.segment(m, lo, hi)
xs = np.linspace(lo, hi, 4000)
rec = probe.evaluate(segs, xs)
err_u = float(np.max(np.abs(np.asarray(m.predict(xs)) - rec)))
err_k = err_u
err_kern = err_k
for s in segs[:-1]:
    k = float(s["right"])
    for xi in (k-0.01, k-0.005, k-0.001, k+0.001, k+0.005, k+0.01):
        e = abs(float(m.predict(xi)) - float(np.asarray(probe.evaluate(segs, xi)).ravel()[0]))
        err_kern = max(err_kern, e)
inf = {
    "segments": len(segs),
    "kinks": [round(s["right"], 6) for s in segs[:-1]],
    "max_uniform_error": round(err_u, 8),
    "max_near_kink_error": round(float(err_kern), 8),
    "validated": bool(err_u < 0.05 and float(err_kern) < 0.05),
}
json.dump(inf, open("/app/inferred.json", "w"), indent=2)
with open("/app/models.md", "w") as f:
    f.write("# item-045-hard recovery\n")
    f.write(f"segments={len(segs)} uniform_err={err_u:.6f} near_kink_err={err_kern:.6f}\n")
assert err_u < 0.05 and float(err_kern) < 0.05, "oracle validation failed"
print("oracle ok", len(segs), err_u, err_kern)
PY