#!/usr/bin/env Rscript
# /app/evaluate.R
# Runs the adaptive rejection sampler implemented in /app/ars.R against the
# target in /app/target.R and checks the statistical quality of the output.
# Writes the samples to /app/samples.tsv (one number per line, no header) and
# a final PASS/FAIL verdict to /app/status.txt.

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
vs <- as.numeric(ars_sample(log_fun, log_deriv, -4, 4, n, seed = 33L))
if (length(vs) != n || anyNA(vs)) stop("sampler returned a bad vector")

write(vs, file = "/app/samples.tsv", ncolumns = 1)

ok <- TRUE
mu <- mean(vs); sdd <- sd(vs)
cat(sprintf("mean=%.4f sd=%.4f n=%d\n", mu, sdd, length(vs)))
if (abs(mu) > 0.15) { ok <- FALSE; cat("FAIL [moment] mean too far from 0\n") }
if (abs(sdd - 1) > 0.15) { ok <- FALSE; cat("FAIL [moment] sd too far from 1\n") }

break_edges <- seq(-4, 4, by = 0.2)
obs <- hist(vs, breaks = break_edges, plot = FALSE)$counts
p <- pnorm_loc(break_edges[-1]) - pnorm_loc(head(break_edges, -1))
chi2 <- sum((obs - n * p)^2 / (n * p))
cat(sprintf("chi2=%.2f (want < 150)\n", chi2))
if (chi2 > 150) { ok <- FALSE; cat("FAIL [chi-square] shape does not match N(0,1)\n") }

if (ok) {
  cat("PASS\n")
  writeLines("PASS", "/app/status.txt")
} else {
  cat("FAIL\n")
  writeLines("FAIL", "/app/status.txt")
}