#!/bin/bash
# Oracle for saffron-dial: author the R library with the two required
# entry-point functions and RUN its self-test to produce the log. Never reads /tests.
set -euo pipefail

cat > /app/diversity.R <<'REOF'
# saffron-dial reef diversity library (base R only)

reef_diversity <- function(counts, base = 2) {
  if (!is.numeric(counts)) {
    stop("counts must be numeric")
  }
  if (length(counts) == 0) {
    return(0)
  }
  if (any(!is.finite(counts))) {
    stop("counts must be finite")
  }
  if (any(counts < 0)) {
    stop("counts must be non-negative")
  }
  if (!is.numeric(base) || length(base) != 1 || !is.finite(base) || base <= 0 || base == 1) {
    stop("base must be a positive number other than 1")
  }
  total <- sum(counts)
  if (total <= 0) {
    return(0)
  }
  p <- counts[counts > 0] / total
  h <- -sum(p * log(p))
  h / log(base)
}

reef_selftest <- function() {
  status <- 0
  check <- function(label, got, want, tol = 1e-8) {
    ok <- is.finite(got) && abs(got - want) <= tol
    if (ok) {
      cat(sprintf("PASS %s (got %.12f)\n", label, got))
    } else {
      cat(sprintf("FAIL %s (got %.12f, want %.12f)\n", label, got, want))
      status <<- 1
    }
  }
  check("equal-two-base2", reef_diversity(c(1, 1)), 1)
  check("four-equal-base2", reef_diversity(c(3, 3, 3, 3)), 2)
  check("single-species", reef_diversity(5), 0)
  check("all-zero", reef_diversity(c(0, 0, 0)), 0)
  check("empty", reef_diversity(numeric(0)), 0)
  check("nats-mixed", reef_diversity(c(10, 0, 6), base = exp(1)), -(10 / 16) * log(10 / 16) - (6 / 16) * log(6 / 16))
  check("unequal-base2", reef_diversity(c(12, 8, 5, 1)), 1.6762400841760658, tol = 1e-6)
  check("zeros-ignored", reef_diversity(c(4, 4, 0, 0)), 1)
  if (status != 0) {
    cat("SELFTEST FAIL\n")
    quit(status = 1)
  }
  cat("SELFTEST PASS\n")
  invisible(0)
}
REOF

cd /app && Rscript -e 'source("/app/diversity.R"); reef_selftest()' > /app/selftest.log 2>&1
cat /app/selftest.log
