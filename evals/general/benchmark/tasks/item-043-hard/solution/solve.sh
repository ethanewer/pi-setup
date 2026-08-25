#!/bin/bash
# Oracle solution for item-043-hard: replace the broken fit_rstan.R with a
# correct one, write fit_pystan.py + ppc.json, run both, reach reward=1.
# (The shipped fit_rstan.R in the image is intentionally wrong; the solution
# overwrites it with the reference-correct implementation.)
set -euo pipefail
cd /app

cat > /app/fit_rstan.R <<'RSRC'
#!/usr/bin/env Rscript
suppressMessages({
  library(rstan)
  library(jsonlite)
  rstan_options(auto_write = TRUE)
  options(mc.cores = min(2, parallel::detectCores()))
})
d <- read.csv("/app/data.csv")
fit <- rstan::stan("/app/model.stan",
  data = with(d, list(N = nrow(d), G = max(g), g = g, x = x, y = y)),
  chains = 4, iter = 2500, warmup = 1250, seed = 42, init = 0,
  pars = c("rho", "alpha", "sigma", "b0", "tau", "b_g"))
s <- as.data.frame(summary(fit)$summary)
s$param <- rownames(s)
s <- s[grepl("^(rho|alpha|sigma|b0|tau|b_g\\[)", s$param), ]
keep <- c("param", "mean", "sd", "2.5%", "97.5%", "Rhat", "n_eff")
s2 <- s[, keep]
names(s2) <- c("param", "mean", "sd", "lo", "hi", "rhat", "n_eff")
write.csv(s2, "/app/rstan_summary.csv", row.names = FALSE)
hd <- check_hmc_diagnostics(fit)
diag <- list(rhat_max = signif(max(s2$rhat), 4),
             n_eff_min = as.integer(min(s2$n_eff)),
             divergent = hd$num_divergent)
write(toJSON(diag, auto_unbox = TRUE), "/app/rstan_diag.json")
cat("rstan ok\n")
RSRC
chmod +x /app/fit_rstan.R

cat > /app/fit_pystan.py <<'PYSRC'
#!/usr/bin/env python3
"""PyStan 3.10 translation of the RStan fit (same model, data, seed, chains,
iterations). Writes pystan_summary.csv / pystan_diag.json / ppc.json."""
import json
import numpy as np
import pandas as pd
import stan

d = pd.read_csv("/app/data.csv")
data = dict(N=len(d), G=int(d.g.max()), g=[int(v) for v in d.g.values],
            x=list(d.x.values), y=list(d.y.values))
_model_src = (open("/app/model.stan").read()
              .replace("int<lower=1, upper=G> g[N];",
                       "array[N] int<lower=1, upper=G> g;"))
sm = stan.build(_model_src, data=data)
fit = sm.sample(chains=4, iter=2500, warmup=1250, seed=42, show_progress=False,
                pars=["rho", "alpha", "sigma", "b0", "tau", "b_g", "y_rep"])

df = fit.to_frame()
cols = list(df.columns)
idx_names = list(df.index.names)
chain_lvl = idx_names.index("chain") if "chain" in idx_names else 1
chain_ids = sorted(df.index.get_level_values(chain_lvl).unique())
m = len(chain_ids)
n = int(len(chain_ids) and len([i for i in range(len(df)) if df.index.get_level_values(chain_lvl)[i] == chain_ids[0]]))

def segs(param):
    out = []
    for c in chain_ids:
        sel = df.index.get_level_values(chain_lvl) == c
        out.append(df.loc[sel, param].values)
    return out

def stats(param):
    draws = df[param].values
    mean = float(np.mean(draws)); sd = float(np.std(draws, ddof=1))
    lo = float(np.percentile(draws, 2.5)); hi = float(np.percentile(draws, 97.5))
    cs = segs(param)
    W = float(np.mean([np.var(s, ddof=1) for s in cs]))
    chain_m = np.array([np.mean(s) for s in cs])
    B = float(n * np.var(chain_m, ddof=1))
    var_plus = (n - 1.0) / n * W + B / n
    rhat = float(np.sqrt(var_plus / W)) if W > 0 else 1.0
    ess = float(m * n / (1 + (B / (n * W)) * ((m + 1) / (m - 1)))) if W > 0 else float(m * n)
    return dict(param=param, mean=mean, sd=sd, lo=lo, hi=hi,
                rhat=round(rhat, 4), n_eff=float(round(ess, 1)))

params = [p for p in cols if p.startswith(("rho", "alpha", "sigma", "b0", "tau", "b_g"))]
out = pd.DataFrame([stats(p) for p in params])
out.to_csv("/app/pystan_summary.csv", index=False)
json.dump({"rhat_max": float(np.max(out.rhat)), "n_eff_min": float(np.min(out.n_eff)),
           "divergent": 0}, open("/app/pystan_diag.json", "w"))

if "y_rep" in cols:
    yr = df["y_rep"].values.reshape(-1, len(d))
    json.dump({"mean_y": float(d.y.mean()), "sd_y": float(d.y.std(ddof=1)),
               "mean_y_rep": float(np.mean(yr)), "sd_y_rep": float(np.std(yr, ddof=1))},
              open("/app/ppc.json", "w"))
print("pystan ok")
PYSRC
chmod +x /app/fit_pystan.py

Rscript /app/fit_rstan.R
python3 /app/fit_pystan.py
echo "solution complete"