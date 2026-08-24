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
vs <- as.numeric(ars_sample(log_fun, log_deriv, -4, 4, n, seed = 7761L))
if (length(vs) != n || anyNA(vs)) quit(status = 5)
write(vs, file = "/app/samples.tsv", ncolumns = 1)
mu <- mean(vs); sdd <- sd(vs)
ok <- TRUE
if (min(vs) < -4.001 || max(vs) > 4.001) ok <- FALSE
if (abs(mu) > 0.2) ok <- FALSE
if (abs(sdd - 1) > 0.15) ok <- FALSE
break_edges <- seq(-4, 4, by = 0.2)
obs <- hist(vs, breaks = break_edges, plot = FALSE)$counts
p <- pnorm_loc(break_edges[-1]) - pnorm_loc(head(break_edges, -1))
chi2 <- sum((obs - n * p)^2 / (n * p))
if (chi2 > 150) ok <- FALSE
if (!ok) quit(status = 1)
EOF

stat_ok=0
if Rscript /tmp/verify.R > /tmp/verify.log 2>&1; then
  stat_ok=1
fi

py_ok=0
if [ -f /app/tests/test_sampler.py ] && [ -s /app/tests/test_sampler.py ]; then
  if (cd /app && python3 -m pytest tests -q > /tmp/pytest.log 2>&1); then
    py_ok=1
  fi
fi

if [ "$stat_ok" = "1" ] && [ "$py_ok" = "1" ]; then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt