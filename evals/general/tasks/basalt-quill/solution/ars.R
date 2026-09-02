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