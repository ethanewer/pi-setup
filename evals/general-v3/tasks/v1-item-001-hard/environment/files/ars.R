# /app/ars.R
# Generic adaptive rejection sampling (current implementation).
#
# ars_sample(log_fun, log_deriv, left, right, n, seed) must draw i.i.d.
# samples from *any* log-concave target supplied through log_fun / log_deriv
# over [left, right]. The implementation below is defective: its output does
# not match a correct target distribution (both T1 and T2 from target.R fail
# the statistical checks in evaluate.R). Repair it. The interface must remain:
#   ars_sample(log_fun, log_deriv, left, right, n, seed) -> length-n numeric

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
      eu <- exp(b * lo); ev <- exp(b * hi)      # <-- examine how the intercept al is (not) used here
      UU <- runif(1)
      ex <- eu + UU * (ev - eu)
      x <- (log(ex) - al) / b
      Elog <- log(ex)
    }
    u <- runif(1)
    hx <- log_fun(x)
    if (u <= exp(hx - Elog)) {
      out <- c(out, x)
    } else {
      if (!any(abs(xs - x) < 1e-12)) xs <- c(xs, x)
    }
  }
  out[1:n]
}