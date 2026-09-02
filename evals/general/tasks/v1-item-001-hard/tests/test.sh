#!/bin/bash
mkdir -p /logs/verifier

reward=0

if [ ! -f /app/ars.R ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

cat > /tmp/verify.R <<'EOF'
source("/app/target.R")
source("/app/ars.R")
# self-contained standard normal CDF (accuracy ~1e-7, no external stats needed)
pnorm_loc <- function(q) {
  sgn <- ifelse(q < 0, -1, 1)
  z <- q / sqrt(2)
  az <- abs(z)
  t <- 1 / (1 + 0.3275911 * az)
  erfc_z <- exp(-az * az) * (t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429)))))
  erf_z <- sgn * (1 - erfc_z)
  0.5 + 0.5 * erf_z
}


n <- 20000L

check_t1 <- function() {
  vs <- as.numeric(ars_sample(log_fun1, log_deriv1, LO1, HI1, n, seed = 7101L))
  if (length(vs) != n || anyNA(vs)) return(FALSE)
  write(vs, file = "/app/samples_t1.tsv", ncolumns = 1)
  ok <- TRUE
  if (min(vs) < -4.001 || max(vs) > 4.001) ok <- FALSE
  mu <- mean(vs); sdd <- sd(vs)
  if (abs(mu) > 0.2) ok <- FALSE
  if (abs(sdd - 1) > 0.15) ok <- FALSE
  be <- seq(-4, 4, by = 0.2)
  obs <- hist(vs, breaks = be, plot = FALSE)$counts
  p <- pnorm_loc(be[-1]) - pnorm_loc(head(be, -1))
  chi2 <- sum((obs - n * p)^2 / (n * p))
  if (chi2 > 100) ok <- FALSE
  ok
}

check_t2 <- function() {
  vs <- as.numeric(ars_sample(log_fun2, log_deriv2, LO2, HI2, n, seed = 7102L))
  if (length(vs) != n || anyNA(vs)) return(FALSE)
  write(vs, file = "/app/samples_t2.tsv", ncolumns = 1)
  ok <- TRUE
  if (min(vs) < -6.001 || max(vs) > 6.001) ok <- FALSE
  mu <- mean(vs); sdd <- sd(vs)
  if (abs(mu) > 0.25) ok <- FALSE
  if (sdd < 0.95 || sdd > 1.35) ok <- FALSE
  b <- 0.8
  F_laplace <- function(x) ifelse(x < -6, 0, ifelse(x >= 6, 1, ifelse(x < 0, 0.5 * exp(x / b), 1 - 0.5 * exp(-x / b))))
  be <- seq(-6, 6, by = 0.3)
  obs <- hist(vs, breaks = be, plot = FALSE)$counts
  p <- F_laplace(be[-1]) - F_laplace(head(be, -1))
  chi2 <- sum((obs - n * p)^2 / (n * p))
  if (chi2 > 120) ok <- FALSE
  ok
}

if (check_t1() && check_t2()) quit(status = 0) else quit(status = 1)
EOF

stat_ok=0
if Rscript /tmp/verify.R > /tmp/verify.log 2>&1; then
  stat_ok=1
fi

py_ok=0
if [ -f /app/tests/test_sampler.py ] && [ -s /app/tests/test_sampler.py ]; then
  if grep -q "samples_t2" /app/tests/test_sampler.py; then
    if grep -q "samples_t1" /app/tests/test_sampler.py; then
      if (cd /app && python3 -m pytest tests -q > /tmp/pytest.log 2>&1); then
        py_ok=1
      fi
    fi
  fi
fi

if [ "$stat_ok" = "1" ] && [ "$py_ok" = "1" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt