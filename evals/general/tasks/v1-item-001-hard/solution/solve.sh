#!/bin/bash
set -euo pipefail

cat > /app/ars.R <<'EOF'
ars_sample <- function(log_fun, log_deriv, left, right, n, seed = 20260730L) {
  set.seed(seed)
  xs <- sort(unique(c(left, -1.5, -0.5, 0, 0.5, 1.5, right)))
  out <- numeric(0)
  while (length(out) < n) {
    xs <- sort(unique(xs))
    m <- length(xs)
    hs <- numeric(m); ss <- numeric(m)
    for (k in 1:m) { hs[k] <- log_fun(xs[k]); ss[k] <- log_deriv(xs[k]) }
    aints <- hs - ss * xs
    zs <- numeric(m - 1)
    for (i in 1:(m - 1)) {
      denom <- ss[i] - ss[i + 1]
      if (abs(denom) < 1e-12) zg <- 0.5 * (xs[i] + xs[i + 1])
      else zg <- (aints[i + 1] - aints[i]) / denom
      zs[i] <- min(max(zg, xs[i]), xs[i + 1])
    }
    lb <- c(left, zs, right)
    lo_all <- hi_all <- b_all <- al_all <- w_all <- numeric(0)
    W <- 0.0
    for (k in 1:m) {
      lo <- max(lb[k], left); hi <- min(lb[k + 1], right)
      if (hi - lo < 1e-14) next
      b <- ss[k]; al <- aints[k]
      if (abs(b) < 1e-12) {
        L <- exp(al) * (hi - lo)
      } else {
        L <- (exp(al + b * hi) - exp(al + b * lo)) / b
      }
      if (L > 0) {
        lo_all <- c(lo_all, lo); hi_all <- c(hi_all, hi)
        b_all <- c(b_all, b); al_all <- c(al_all, al); w_all <- c(w_all, L)
        W <- W + L
      }
    }
    if (W <= 0) stop("ARS: zero proposal mass")
    r <- runif(1) * W
    acc <- 0.0; j <- 0L
    for (kk in 1:length(w_all)) { acc <- acc + w_all[kk]; if (r <= acc) { j <- kk; break } }
    if (j == 0L) j <- length(w_all)
    lo <- lo_all[j]; hi <- hi_all[j]; b <- b_all[j]; al <- al_all[j]
    if (abs(b) < 1e-12) {
      x <- runif(1, lo, hi)
      Elog <- al
    } else {
      eu <- exp(al + b * lo); ev <- exp(al + b * hi)
      UU <- runif(1)
      ex <- eu + UU * (ev - eu)
      x <- (log(ex) - al) / b
      Elog <- log(ex)
    }
    u <- runif(1)
    hx <- log_fun(x)
    if (hx > -Inf && u <= exp(hx - Elog)) {
      out <- c(out, x)
    } else {
      if (!any(abs(xs - x) < 1e-12)) xs <- c(xs, x)
    }
  }
  out[1:n]
}
EOF

Rscript /app/evaluate.R

mkdir -p /app/tests
cat > /app/tests/test_sampler.py <<'PYEOF'
import math


def _load(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(float(line))
    return vals


def _phif(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def _laplace_cdf(x):
    if x < -6:
        return 0.0
    if x >= 6:
        return 1.0
    return 0.5 * math.exp(x / 0.8) if x < 0 else 1.0 - 0.5 * math.exp(-x / 0.8)


def _chi2(vals, edges, cdf):
    n = len(vals)
    chi = 0.0
    for j in range(len(edges) - 1):
        c = sum(1 for x in vals if edges[j] <= x < edges[j + 1])
        e = n * (cdf(edges[j + 1]) - cdf(edges[j]))
        if e > 0:
            chi += (c - e) ** 2 / e
    return chi


# -- T1: standard normal on [-4,4] --
def test_t1_count_and_bounds():
    vals = _load("/app/samples_t1.tsv")
    assert len(vals) == 20000
    assert all(-4.0 - 1e-9 <= x <= 4.0 + 1e-9 for x in vals)


def test_t1_moments():
    vals = _load("/app/samples_t1.tsv")
    mu = sum(vals) / len(vals)
    sd = math.sqrt(sum((x - mu) ** 2 for x in vals) / (len(vals) - 1.0))
    assert abs(mu) < 0.2
    assert 0.85 < sd < 1.15


def test_t1_chisquare():
    vals = _load("/app/samples_t1.tsv")
    edges = [-4.0 + 0.2 * i for i in range(41)]
    assert _chi2(vals, edges, _phif) < 100


# -- T2: Laplace(0, 0.8) on [-6,6] --
def test_t2_count_and_bounds():
    vals = _load("/app/samples_t2.tsv")
    assert len(vals) == 20000
    assert all(-6.0 - 1e-9 <= x <= 6.0 + 1e-9 for x in vals)


def test_t2_moments():
    vals = _load("/app/samples_t2.tsv")
    mu = sum(vals) / len(vals)
    sd = math.sqrt(sum((x - mu) ** 2 for x in vals) / (len(vals) - 1.0))
    assert abs(mu) < 0.25
    assert 0.95 < sd < 1.35


def test_t2_chisquare():
    vals = _load("/app/samples_t2.tsv")
    edges = [-6.0 + 0.3 * i for i in range(41)]
    assert _chi2(vals, edges, _laplace_cdf) < 120
PYEOF

cd /app && python3 -m pytest tests -q