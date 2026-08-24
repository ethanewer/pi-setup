#!/usr/bin/env Rscript
# RStan fit (item-043 HARD). This file is SHIPPED BROKEN — see README.md.
# Find and fix every defect so the summaries satisfy the contract.
suppressMessages({
  library(rstan)
  library(jsonlite)
  rstan_options(auto_write = TRUE)
  options(mc.cores = min(2, parallel::detectCores()))
})
d <- read.csv("/app/data.csv")
fit <- rstan::stan("/app/model.stan",
  data = with(d, list(N = nrow(d), G = max(g), g = g, x = x, y = y)),
  chains = 2, iter = 300, warmup = 150, seed = 7, init = 0,
  pars = c("rho", "alpha"))                       # FIX: missing parameters
s <- as.data.frame(summary(fit)$summary)
s$param <- rownames(s)
s2 <- s[grepl("^(rho|alpha|sigma|b0|tau|b_g\\[)", s$param),
        c("param", "mean", "sd", "2.5%", "97.5%", "Rhat", "n_eff")]
names(s2) <- c("param", "mean", "sd", "lo", "hi", "rhat", "n_eff")
write.csv(s2, "/app/rstan_summary.csv", row.names = FALSE)
hd <- check_hmc_diagnostics(fit)
write(toJSON(list(rhat_max = signif(max(s2$rhat), 4),
                  n_eff_min = as.integer(min(s2$n_eff)),
                  divergent = hd$num_divergent), auto_unbox = TRUE,
             digits = I(4)), "/app/rstan_diag.json")
cat("rstan ran\n")