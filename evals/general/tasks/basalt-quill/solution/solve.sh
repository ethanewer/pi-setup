#!/usr/bin/env bash
# Oracle for basalt-quill: build all seven deliverables by real work.
set -euo pipefail
cd /app

# ---- 1) lorentzian spectrum fitter + results ----
cat > /app/fit_spectra.py <<'PYFIT'
#!/usr/bin/env python3
"""fit_spectra.py -- crop each spectral peak's local window and fit a
lorentzian profile (center / width / amplitude / offset).

Usage:
    python3 fit_spectra.py <input.csv> -o <out.json>

Input CSV has a header `wavelength,intensity`. One or more peaks are detected;
each is cropped to its local valve-to-valve window and fitted with

    y(x) = offset + amplitude * width^2 / ((x - center)^2 + width^2)

Output JSON: {"peaks": [ {center,width,amplitude,offset}, ... ]}

Edge behaviour:
  * a spectrum with no detectable peaks yields {"peaks": []}
  * a constant/shallow spectrum yields {"peaks": []}
  * empty or header-only input yields {"peaks": []}
"""
import argparse
import csv
import json

import numpy as np
from scipy.optimize import curve_fit


def lorentzian(x, center, width, amplitude, off):
    return off + amplitude * (width * width) / ((x - center) ** 2 + width * width)


def _read(path):
    xs = []
    ys = []
    with open(path, newline="") as fh:
        reader = csv.reader(fh)
        next(reader, None)  # header
        for row in reader:
            if not row or len(row) < 2:
                continue
            xs.append(float(row[0]))
            ys.append(float(row[1]))
    return np.asarray(xs, float), np.asarray(ys, float)


def _is_valley(y, i):
    n = len(y)
    if i <= 0 or i >= n - 1:
        return True
    return y[i] <= y[i - 1] and y[i] <= y[i + 1]


def _base_value(y, i):
    """Value of the trough just left and just right of index i."""
    n = len(y)
    left = 0
    while left < i and not _is_valley(y, left):
        left += 1
    right = n - 1
    while right > i and not _is_valley(y, right):
        right -= 1
    return min(float(y[left]), float(y[right]))


def detect_peaks(y):
    """Strict local maxima with meaningful local prominence."""
    n = len(y)
    if n < 3:
        return []
    rng = float(y.max()) - float(y.min())
    if rng <= 0:
        return []
    thr = 0.05 * rng
    peaks = []
    for i in range(1, n - 1):
        if y[i] > y[i - 1] and y[i] > y[i + 1]:
            if float(y[i]) - _base_value(y, i) >= thr:
                peaks.append(i)
    return peaks


def fit_one(x, y, p):
    n = len(x)
    left = p
    while left > 0 and not _is_valley(y, left - 1):
        left -= 1
    right = p
    while right < n - 1 and not _is_valley(y, right + 1):
        right += 1
    xw = x[left:right + 1]
    yw = y[left:right + 1]
    if len(xw) < 6:
        return None
    off0 = float(min(yw[0], yw[-1]))
    c0 = float(x[p])
    a0 = float(y[p] - off0)
    if a0 <= 0:
        return None
    w0 = 1.0
    half = off0 + a0 / 2.0
    for direction in (1, -1):
        j = p
        while 0 <= j < n and y[j] >= half:
            j += direction
        if 0 <= j < n:
            w0 = max(w0, abs(float(x[j]) - c0))
    try:
        popt, _ = curve_fit(
            lorentzian, xw, yw, p0=[c0, w0, a0, off0],
            bounds=(
                [c0 - 4.0, 1e-9, 1e-9, yw.min() - 2.0],
                [c0 + 4.0, 1e6, 1e9, yw.max() + 2.0],
            ),
            maxfev=30000,
        )
        c, w, a, off = popt
        return {
            "center": float(c),
            "width": float(w),
            "amplitude": float(a),
            "offset": float(off),
        }
    except Exception:  # noqa: BLE001
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    x, y = _read(args.input)
    peaks = []
    if len(x) >= 3:
        for p in detect_peaks(y):
            hit = fit_one(x, y, p)
            if hit is not None:
                peaks.append(hit)
    peaks.sort(key=lambda d: d["center"])
    with open(args.output, "w") as f:
        json.dump({"peaks": peaks}, f)


if __name__ == "__main__":
    main()
PYFIT
python3 /app/fit_spectra.py /app/spectrum.csv -o /app/fit_results.json

# ---- 2) compound-model separability + matrix ----
cat > /app/stack_models.py <<'PYSTACK'
#!/usr/bin/env python3
"""stack_models.py -- build nested / stacked / blocked compound astropy
models from a JSON spec and compute the correct separability matrix.

Usage:
    python3 stack_models.py <spec.json> -o <out.json>

Spec format (nested expression tree):
    {"op": "cat",  "a": EXPR, "b": EXPR}   # block / concatenate submodels
    {"op": "pipe","a": EXPR, "b": EXPR}   # stack (a applied first, then b)
    leaf EXPR (one of):
        {"leaf":"shift",        "offset": F}
        {"leaf":"scale",        "factor": F}
        {"leaf":"linear",       "slope": F, "intercept": F}
        {"leaf":"mapping",      "n_in": I, "index": [ints]}
        {"leaf":"poly2d",       "degree": I, "coeffs": {"c0_0":F, ...}}
        {"leaf":"rotation",     "angle": F}

Output JSON: {"n_inputs": M, "n_outputs": N, "matrix": [[0/1 x N], ......]}
Entry [i][j] of `matrix` is 1 when output i depends on input j (so the shape
is N-rows by M-columns when M different i/o values are present).
"""
import argparse
import json

import numpy as np


def build_model(expr):
    """Construct an astropy compound model from a JSON spec `expr`."""
    from astropy.modeling import models
    from astropy.modeling.mappings import Mapping

    op = expr.get("op")
    lk = "a" if "a" in expr else "left"
    rk = "b" if "b" in expr else "right"
    if op == "cat":
        return build_model(expr[lk]) & build_model(expr[rk])
    if op == "pipe":
        return build_model(expr[lk]) | build_model(expr[rk])
    leaf = expr["leaf"]
    if leaf == "shift":
        return models.Shift(offset=expr["offset"])
    if leaf == "scale":
        return models.Scale(factor=expr["factor"])
    if leaf == "linear":
        return models.Linear1D(slope=expr["slope"], intercept=expr["intercept"])
    if leaf == "mapping":
        return Mapping(expr["index"], n_inputs=expr["n_in"])
    if leaf == "poly2d":
        from astropy.modeling.models import Polynomial2D
        return Polynomial2D(expr["degree"], **expr["coeffs"])
    if leaf == "rotation":
        from astropy.modeling.models import Rotation2D
        return Rotation2D(expr["angle"])
    raise ValueError("unknown leaf: %r" % leaf)


def separability_matrix(model):
    """Return the (n_outputs, n_inputs) 0/1 separability matrix of `model`.

    Entry [i, j] is 1 when output i depends on input j.
    """
    from astropy.modeling import mappings
    from astropy.modeling.core import CompoundModel, Model

    if model.n_inputs == 1 and model.n_outputs > 1:
        return np.ones((model.n_outputs, model.n_inputs), dtype=int)

    def coord_matrix(m, pos, nout):
        if isinstance(m, mappings.Mapping):
            axes = []
            for idx in m.mapping:
                axis = np.zeros((m.n_inputs,))
                axis[idx % m.n_inputs] = 1
                axes.append(axis)
            cm = np.vstack(axes)
        elif not m.separable:
            cm = np.ones((m.n_outputs, m.n_inputs))
        else:
            cm = np.eye(m.n_inputs)
        mat = np.zeros((nout, m.n_inputs), dtype=int)
        if pos == "left":
            mat[: m.n_outputs, : m.n_inputs] = cm
        else:
            mat[-m.n_outputs:, -m.n_inputs:] = cm
        return mat

    def cstack(left, right):
        lnout = left.n_outputs if isinstance(left, Model) else left.shape[0]
        rnout = right.n_outputs if isinstance(right, Model) else right.shape[0]
        noutp = lnout + rnout
        if isinstance(left, Model):
            cleft = coord_matrix(left, "left", noutp)
        else:
            cleft = np.zeros((noutp, left.shape[1]), dtype=int)
            cleft[: left.shape[0], : left.shape[1]] = left
        if isinstance(right, Model):
            cright = coord_matrix(right, "right", noutp)
        else:
            cright = np.zeros((noutp, right.shape[1]), dtype=int)
            cright[-right.shape[0]:, -right.shape[1]:] = right
        return np.hstack([cleft, cright])

    def cdot(left, right):
        left, right = right, left
        cleft = coord_matrix(left, "left", left.n_outputs) if isinstance(left, Model) else left
        cright = coord_matrix(right, "right", right.n_outputs) if isinstance(right, Model) else right
        return np.dot(cleft, cright)

    def sep(t):
        if isinstance(t, CompoundModel):
            sl = sep(t.left)
            sr = sep(t.right)
            if t.op == "&":
                return cstack(sl, sr)
            if t.op == "|":
                return cdot(sl, sr)
            return np.ones((t.n_outputs, t.n_inputs), dtype=int)
        return coord_matrix(t, "left", t.n_outputs)

    return np.where(sep(model) != 0, True, False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    with open(args.spec) as f:
        expr = json.load(f)
    model = build_model(expr)
    m = int(model.n_inputs)
    n = int(model.n_outputs)
    matrix = separability_matrix(model).tolist()
    with open(args.output, "w") as f:
        json.dump({"n_inputs": m, "n_outputs": n, "matrix": matrix}, f)


if __name__ == "__main__":
    main()
PYSTACK
python3 /app/stack_models.py /app/spec_default.json -o /app/separability.json

# ---- 3) cross-entropy optimizer with prefix memo ----
cat > /app/cross_entropy_opt.py <<'PYCE'
#!/usr/bin/env python3
"""cross_entropy_opt.py -- a cross-entropy optimizer that memoizes shared
prefix computation.

Planning score (documented reward, must stay stable):

   freq = [0]*K
   value = 0.0
   for i in range(L):
       a = int(seq[i]); freq[a] += 1
       value += W[i][a]
       if freq[a] > 1:
           value += BP[i][freq[a]]
       value += float(XC[i].dot(freq))     # state-interaction term

   score(seq) = value

W is (L, K); BP is (L, L+1); XC is (L, K).  BP[i][r] is the repeat-bonus paid
when action at position i becomes the r-th occurrence of its symbol (r >= 2).
A memo cache keyed on shared prefixes reuses the intermediate (value,
count-vector) state so batches of near-identical sequences are scored far
faster than recomputing every prefix from scratch.

Subcommands
-----------
  optimize --spec in.json -o out.json
      runs n_iterations of cross-entropy sampling + elite re-estimation and
      writes {"final_theta","history","rows","cols","improvement"}.
  memo --spec in.json -o out.json
      scores the given sequences both with and without prefix memoization and
      writes {"scores","speedup","max_abs_diff"}.
"""
import argparse
import json
import time

import numpy as np


# ---------------------------------------------------------------------------
# Reward
# ---------------------------------------------------------------------------
def score(seq, W, BP, XC):
    L, K = W.shape
    freq = np.zeros(K, dtype=int)
    value = 0.0
    for i in range(L):
        a = int(seq[i])
        freq[a] += 1
        value += W[i][a]
        if freq[a] > 1:
            value += BP[i][freq[a]]
        value += float(XC[i].dot(freq))
    return value


def _brute_scores(seqs, W, BP, XC):
    return np.array([score(s, W, BP, XC) for s in seqs])


def memoized_scores(seqs, W, BP, XC, _key_hint=None):
    """Score `seqs` caching every shared prefix with a trie keyed on integer
    node ids (Sequence -> unique prefix node), so extending an already-scored
    prefix is O(1) rather than re-deriving the shared computation.

    `_key_hint` is unused; it documents that numpy array keys can be passed.
    """
    L, K = W.shape
    children = {0: {}}
    state = {0: (0.0, np.zeros(K, dtype=int))}
    next_id = 1
    out = np.empty(len(seqs), dtype=float)
    for r, s in enumerate(seqs):
        a = np.asarray(s, dtype=np.int64).reshape(-1)
        node = 0
        value, freq = state[node]
        p = 0
        while p < L:
            child = children[node].get(a[p])
            if child is None:
                break
            node = child
            value, freq = state[node]
            p += 1
        freq = freq.copy()
        for q in range(p, L):
            idx = a[q]
            freq[idx] += 1
            value += W[q][idx]
            if freq[idx] > 1:
                value += BP[q][freq[idx]]
            value += float(XC[q].dot(freq))
            child = next_id
            next_id += 1
            children[node][idx] = child
            children[child] = {}
            state[child] = (value, freq.copy())
            node = child
        out[r] = value
    return out


def _timeit(fn, n=5):
    best = None
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        dt = time.perf_counter() - t0
        best = dt if best is None else min(best, dt)
    return best


# ---------------------------------------------------------------------------
# Optimizer (cross-entropy method)
# ---------------------------------------------------------------------------
def sample_sequences(theta, n_samples, rng):
    L, K = theta.shape
    out = np.empty((n_samples, L), dtype=int)
    for i in range(L):
        out[:, i] = rng.choice(K, size=n_samples, p=theta[i])
    return out


def optimize(theta0, W, BP, XC, n_samples=1200, elite=180, n_iterations=9, seed=7):
    """Run cross-entropy optimization; returns (theta_final, history, seed)."""
    rng = np.random.default_rng(seed)
    L, K = theta0.shape
    theta = np.clip(np.asarray(theta0, float), 1e-5, None)
    theta = theta / theta.sum(axis=1, keepdims=True)
    history = []
    for _ in range(n_iterations):
        X = sample_sequences(theta, n_samples, rng)
        scores = memoized_scores(X, W, BP, XC)
        order = np.argsort(scores)[::-1][:elite]
        elite_X = X[order]
        counts = np.zeros((L, K), dtype=float)
        for i in range(L):
            counts[i] = np.bincount(elite_X[:, i], minlength=K)
        theta = (counts + 1.0) / (elite_X.shape[0] + K)
        history.append(float(scores[order].mean()))
    return theta, history, seed


def _load(f):
    with open(f) as fh:
        return json.load(fh)


def cmd_optimize(args):
    spec = _load(args.spec)
    W = np.asarray(spec["W"], float)
    BP = np.asarray(spec["BP"], float)
    XC = np.asarray(spec.get("XC", np.zeros((len(W), len(W[0])))), float)
    theta0 = np.asarray(spec["theta0"], float)
    n_iterations = int(spec.get("n_iterations", 8))
    n_samples = int(spec.get("n_samples", 1200))
    seed = int(spec.get("seed", 7))
    theta, history, _ = optimize(theta0, W, BP, XC, n_samples=n_samples,
                                 n_iterations=n_iterations, seed=seed)
    out = {
        "rows": int(theta.shape[0]),
        "cols": int(theta.shape[1]),
        "final_theta": theta.tolist(),
        "history": history,
        "improvement": float(history[-1] - history[0]),
    }
    with open(args.output, "w") as f:
        json.dump(out, f)


def cmd_memo(args):
    spec = _load(args.spec)
    W = np.asarray(spec["W"], float)
    BP = np.asarray(spec["BP"], float)
    XC = np.asarray(spec.get("XC", np.zeros((len(W), len(W[0])))), float)
    seqs = spec["sequences"]
    brute = _brute_scores(seqs, W, BP, XC)
    memo = memoized_scores(seqs, W, BP, XC)
    d = float(np.max(np.abs(brute - memo))) if len(brute) else 0.0
    t_b = _timeit(lambda: _brute_scores(seqs, W, BP, XC))
    t_m = _timeit(lambda: memoized_scores(seqs, W, BP, XC))
    out = {
        "scores": memo.tolist(),
        "speedup": float(t_b / t_m) if t_m > 0 else 1.0,
        "max_abs_diff": d,
    }
    with open(args.output, "w") as f:
        json.dump(out, f)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p1 = sub.add_parser("optimize")
    p1.add_argument("--spec", required=True)
    p1.add_argument("-o", "--output", required=True)
    p1.set_defaults(func=cmd_optimize)
    p2 = sub.add_parser("memo")
    p2.add_argument("--spec", required=True)
    p2.add_argument("-o", "--output", required=True)
    p2.set_defaults(func=cmd_memo)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
PYCE

# ---- 4) adaptive rejection sampler (R) + empirical sample ----
cat > /app/ars.R <<'RSARS'
### ars.R -- adaptive rejection sampling for a log-concave target density.
###
### Exposes a single function:
###   ars(logf, lo, hi, n, init = NULL, seed = 1) -> numeric vector of `n`
###       samples from the unnormalized density ~ exp(logf(x)) on [lo, hi].
###
### `logf` must be log-concave on (lo, hi) and return finite values there.
### The sampler builds an adaptive piecewise-exponential (tangent-line) upper
### hull of the log-density: sample from the envelope, accept/reject against
### exp(logf(x)), and add rejected points to the support (adapt) to tighten
### the squeeze.

ars <- function(logf, lo, hi, n, init = NULL, seed = 1) {
  set.seed(seed)

  if (is.null(init)) {
    init <- c(lo + (hi - lo) * 0.15,
              lo + (hi - lo) * 0.50,
              lo + (hi - lo) * 0.85)
  }
  init <- init[init > lo & init < hi]
  if (length(init) < 2) {
    eps <- (hi - lo) * 1e-4
    init <- c(lo + eps, hi - eps)
  }

  # numerical first derivative of logf
  deriv <- function(x) {
    e <- 1e-5 * (1 + abs(x))
    (logf(x + e) - logf(x)) / e
  }

  # rebuild hull over current sorted support
  build <- function(spt) {
    k <- length(spt)
    h <- vapply(spt, logf, numeric(1))
    dp <- vapply(spt, deriv, numeric(1))
    # tangent intersection points z between consecutive support points
    if (k > 1) {
      z <- numeric(k - 1)
      for (j in 1:(k - 1)) {
        den <- dp[j] - dp[j + 1]
        if (den == 0) den <- 1e-9
        z[j] <- (h[j + 1] - h[j] + dp[j] * spt[j] - dp[j + 1] * spt[j + 1]) / den
      }
    } else {
      z <- numeric(0)
    }
    list(x = spt, h = h, dp = dp, b = c(lo, z, hi))
  }

  spt <- sort(unique(init))
  env <- build(spt)

  # piecewise-exp sampler: returns x from the hull and the log hull height u
  sample_hull <- function(env) {
    x <- env$x; h <- env$h; dp <- env$dp; b <- env$b
    k <- length(x)
    # area of each piece under exp(line)
    area <- numeric(k)
    for (j in 1:k) {
      ta <- h[j] + dp[j] * (b[j] - x[j])
      tb <- h[j] + dp[j] * (b[j + 1] - x[j])
      if (abs(dp[j]) < 1e-12) {
        area[j] <- (b[j + 1] - b[j]) * exp(ta)
      } else {
        area[j] <- (exp(tb) - exp(ta)) / dp[j]
      }
      if (!is.finite(area[j]) || area[j] < 0) area[j] <- .Machine$double.xmin
    }
    total <- sum(area)
    if (!is.finite(total) || total <= 0) total <- 1
    u <- runif(1) * total
    j <- 1
    while (j < k && u > area[j]) { u <- u - area[j]; j <- j + 1 }
    j <- min(j, k)
    # inverse-CDF within piece j (truncated exponential)
    Xj <- x[j]; H <- h[j]; D <- dp[j]; xa <- b[j]; xb <- b[j + 1]
    ta <- H + D * (xa - Xj)
    tb <- H + D * (xb - Xj)
    if (D == 0) {
      xs <- xa + runif(1) * (xb - xa)
      loghull <- ta
    } else {
      # u in [0,1] within the piece
      fu <- runif(1)
      # exp line at x = exp(ta) + fu * (exp(tb) - exp(ta))
      # renormalized to avoid overflow
      lta <- ta; ltb <- tb
      mx <- max(lta, ltb)
      ea <- exp(lta - mx); eb <- exp(ltb - mx)
      Ex <- ea + fu * (eb - ea)
      Tx <- mx + log(Ex)             # log envelope at sampled x
      xs <- Xj + (Tx - H) / D
      loghull <- Tx
    }
    xs <- min(max(xs, lo), hi)
    list(x = xs, loghull = loghull)
  }

  out <- numeric(n)
  filled <- 0L
  attempts <- 0L
  max_attempts <- n * 1000000L + 1000L

  while (filled < n && attempts < max_attempts) {
    attempts <- attempts + 1L
    s <- sample_hull(env)
    lx <- logf(s$x)
    if (runif(1) <= exp(lx - s$loghull)) {
      filled <- filled + 1L
      out[filled] <- s$x
    } else {
      # adapt: add rejected point to support (if it is interior and distinct)
      if (lx > -Inf && is.finite(s$x) && !any(abs(spt - s$x) < 1e-9)) {
        spt <- sort(c(spt, s$x))
        env <- build(spt)
      }
    }
  }
  out
}
RSARS
Rscript --vanilla -e "suppressMessages(source('/app/ars.R')); s <- ars(function(x) -0.5*x^2, -8, 8, 2000, seed=1); write.csv(data.frame(value=s), '/app/sample.csv', row.names=FALSE)"

echo 'ORACLE_DONE'
