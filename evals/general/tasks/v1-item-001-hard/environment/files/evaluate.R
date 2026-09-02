#!/usr/bin/env Rscript
# /app/evaluate.R
# Runs the generic adaptive rejection sampler in /app/ars.R on both
# log-concave targets declared in /app/target.R and checks the statistical
# quality of each output. Writes the samples to /app/samples_t1.tsv and
# /app/samples_t2.tsv (one number per line) and a PASS/FAIL verdict to
# /app/status.txt.

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


check_t1 <- function() {
  n <- 20000L
  vs <- as.numeric(ars_sample(log_fun1, log_deriv1, LO1, HI1, n, seed = 51L))
  if (length(vs) != n || anyNA(vs)) { cat("T1: bad vector returned\n"); return(FALSE) }
  write(vs, file = "/app/samples_t1.tsv", ncolumns = 1)
  ok <- TRUE
  mu <- mean(vs); sdd <- sd(vs)
  cat(sprintf("T1  mean=%.4f sd=%.4f\n", mu, sdd))
  if (abs(mu) > 0.2) { ok <- FALSE; cat("T1 FAIL [moment] mean\n") }
  if (abs(sdd - 1) > 0.15) { ok <- FALSE; cat("T1 FAIL [moment] sd\n") }
  be <- seq(-4, 4, by = 0.2)
  obs <- hist(vs, breaks = be, plot = FALSE)$counts
  p <- pnorm_loc(be[-1]) - pnorm_loc(head(be, -1))
  chi2 <- sum((obs - n * p)^2 / (n * p))
  cat(sprintf("T1  chi2=%.2f (want < 100)\n", chi2))
  if (chi2 > 100) { ok <- FALSE; cat("T1 FAIL [chi-square]\n") }
  ok
}

check_t2 <- function() {
  n <- 20000L
  vs <- as.numeric(ars_sample(log_fun2, log_deriv2, LO2, HI2, n, seed = 52L))
  if (length(vs) != n || anyNA(vs)) { cat("T2: bad vector returned\n"); return(FALSE) }
  write(vs, file = "/app/samples_t2.tsv", ncolumns = 1)
  ok <- TRUE
  mu <- mean(vs); sdd <- sd(vs)
  cat(sprintf("T2  mean=%.4f sd=%.4f\n", mu, sdd))
  if (abs(mu) > 0.25) { ok <- FALSE; cat("T2 FAIL [moment] mean\n") }
  if (sdd < 0.95 || sdd > 1.35) { ok <- FALSE; cat("T2 FAIL [moment] sd (Laplace sd is ~1.13)\n") }
  b <- 0.8
  F_laplace <- function(x) ifelse(x < -6, 0, ifelse(x >= 6, 1, ifelse(x < 0, 0.5 * exp(x / b), 1 - 0.5 * exp(-x / b))))
  be <- seq(-6, 6, by = 0.3)
  obs <- hist(vs, breaks = be, plot = FALSE)$counts
  p <- F_laplace(be[-1]) - F_laplace(head(be, -1))
  chi2 <- sum((obs - n * p)^2 / (n * p))
  cat(sprintf("T2  chi2=%.2f (want < 120)\n", chi2))
  if (chi2 > 120) { ok <- FALSE; cat("T2 FAIL [chi-square]\n") }
  ok
}

r1 <- check_t1()
r2 <- check_t2()
if (r1 && r2) {
  cat("PASS\n")
  writeLines("PASS", "/app/status.txt")
} else {
  cat("FAIL\n")
  writeLines("FAIL", "/app/status.txt")
}