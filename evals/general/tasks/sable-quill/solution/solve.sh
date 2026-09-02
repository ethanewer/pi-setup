#!/bin/bash
# sable-quill oracle: author the R module deliverable, then run its self-test
# to produce the recorded log. Never reads /tests.
set -eu

cat > /app/tidekit.R <<'RS'
# tidekit.R — Sable Quill estuarine gauge Monte-Carlo module

tide_estimate <- function(n, rate = 0.4) {
  if (!is.numeric(n) || length(n) != 1 || is.na(n) || !is.finite(n) || n < 1) {
    stop("tide_estimate: n must be a finite number >= 1")
  }
  if (!is.numeric(rate) || length(rate) != 1 || is.na(rate) || !is.finite(rate) || rate <= 0) {
    stop("tide_estimate: rate must be a finite positive number")
  }
  set.seed(20240617)
  draws <- stats::rexp(n, rate = rate)
  mean(draws)
}

tide_selftest <- function() {
  target <- 1 / 0.4
  est <- tide_estimate(20000, rate = 0.4)
  tol <- 0.05 * target
  if (is.finite(est) && abs(est - target) <= tol) {
    cat(sprintf("PASS tide_estimate(20000, rate=0.4) = %.6f (target %.6f, tol %.6f)\n",
                est, target, tol))
    quit(status = 0)
  } else {
    cat(sprintf("FAIL tide_estimate(20000, rate=0.4) = %.6f (target %.6f, tol %.6f)\n",
                est, target, tol))
    quit(status = 1)
  }
}
RS

cd /app
Rscript -e 'source("/app/tidekit.R"); tide_selftest()' > /app/selftest.log 2>&1
cat /app/selftest.log

echo "solve.sh done -> /app/tidekit.R and /app/selftest.log"
ls -l /app/tidekit.R /app/selftest.log
