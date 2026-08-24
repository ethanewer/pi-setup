#!/bin/bash
# Oracle solution for skill-rstan-2-32-7: write and run /app/fit.r.
set -euo pipefail

cat > /app/fit.r <<'RSRC'
suppressMessages({
  library(rstan)
  library(jsonlite)
  rstan_options(auto_write = TRUE)
  options(mc.cores = min(2, parallel::detectCores()))
})
d <- read.csv("/app/data.csv")
fit <- rstan::stan("/app/model.stan",
  data = list(N = nrow(d), y = d$y),
  chains = 2, iter = 1200, warmup = 600, seed = 42, init = 0, pars = c("mu"))
sm <- as.data.frame(summary(fit)$summary)
sm$param <- rownames(sm)
mu_mean <- signif(as.numeric(sm$mean[sm$param == "mu"])[1], 4)
write.csv(data.frame(v = mu_mean), "/app/result.csv", row.names = FALSE)
cat("fit ok\n")
RSRC

Rscript /app/fit.r
echo "solution wrote /app/result.csv"