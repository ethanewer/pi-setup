#!/bin/bash
# Oracle for wren-forge: author the Stan program and the R driver, then RUN the
# driver on the visible fixtures to produce /app/posterior.csv and
# /app/summary.json. Never reads /tests.
set -eu

# ---- 1. The driver (contains the Stan program — this IS the work) -----------
cat > /app/fit.R <<'RSCRIPT'
#!/usr/bin/env Rscript
suppressMessages(library(rstan))
suppressMessages(library(jsonlite))

STAN_SRC <- '
data {
  int<lower=1> G;
  array[G] int<lower=1> n;
  array[G] int<lower=0> k;
}
parameters {
  real<lower=0> alpha;
  real<lower=0> beta;
  vector<lower=0,upper=1>[G] theta;
}
model {
  // Jeffreys-type hyper-prior over the (alpha, beta) pair
  target += -0.5 * log(alpha) - 0.5 * log(beta) - 0.5 * log(alpha + beta);
  // shared beta group prior
  theta ~ beta(alpha, beta);
  // per-group binomial likelihood
  k ~ binomial(n, theta);
}
'

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  cat("usage: fit.R <trials.csv> <outdir>\n", file = stderr())
  quit(status = 2)
}
csv_path <- args[1]
outdir <- args[2]
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

d <- tryCatch(read.csv(csv_path, stringsAsFactors = FALSE, colClasses = "character"),
              error = function(e) NULL)
if (is.null(d)) {
  cat("cannot read csv: ", csv_path, "\n", file = stderr())
  quit(status = 1)
}
if (!identical(names(d), c("batch", "trials", "germinated"))) {
  cat("csv header must be batch,trials,germinated\n", file = stderr())
  quit(status = 1)
}
trials <- suppressWarnings(as.integer(d$trials))
germ <- suppressWarnings(as.integer(d$germinated))
if (nrow(d) < 2 || any(is.na(trials)) || any(is.na(germ)) ||
    any(trials < 1) || any(germ < 0) || any(germ > trials)) {
  cat("invalid trial table (need >=2 rows, trials >= 1, 0 <= germinated <= trials)\n",
      file = stderr())
  quit(status = 1)
}

writeLines(STAN_SRC, file.path(outdir, "hier_model.stan"))

sm <- stan_model(model_code = STAN_SRC)
dat <- list(G = nrow(d), n = trials, k = germ)
fit <- sampling(sm, data = dat, chains = 2, warmup = 400, iter = 1000,
                seed = 20240607L, refresh = 0)

dr <- extract(fit, pars = c("theta", "alpha", "beta"))
theta <- dr$theta  # draws x G
post <- cbind(theta, alpha = dr$alpha, beta = dr$beta)
colnames(post) <- c(paste0("theta", seq_len(nrow(d))), "alpha", "beta")
write.table(post, file.path(outdir, "posterior.csv"), sep = ",",
            row.names = FALSE, col.names = TRUE, quote = FALSE)

summ <- list(
  groups = nrow(d),
  batch_ids = d$batch,
  theta_mean = as.numeric(colMeans(theta)),
  alpha_mean = mean(dr$alpha),
  beta_mean = mean(dr$beta),
  n_draws = nrow(post),
  seed = 20240607L
)
writeLines(toJSON(summ, auto_unbox = TRUE, digits = 10),
           file.path(outdir, "summary.json"))

cat("FIT_OK groups=", nrow(d), " draws=", nrow(post), "\n", sep = "")
RSCRIPT

chmod +x /app/fit.R

# ---- 2. Produce the visible deliverables by actually running ----------------
Rscript /app/fit.R /app/trials.csv /app

echo "solve.sh done"
ls -l /app/fit.R /app/hier_model.stan /app/posterior.csv /app/summary.json
