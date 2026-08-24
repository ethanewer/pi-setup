# skill-rstan-2-32-7 — fit a normal model with RStan 2.32.7 and report `mu`

This environment has RStan **2.32.7** (an R package) installed, plus the C++
toolchain it needs to compile Stan models at runtime. Two files are provided:
- `/app/model.stan` — a simple normal model with a broad prior on `mu` and
  `sigma`.
- `/app/data.csv` — 12 iid observations centered near `10.0` (single column,
  header `y`, then repeated rows).

Your only task: **fit that model with RStan and report the posterior mean of
`mu`**, demonstrating the core RStan workflow (compile model, sample with a
fixed seed, read the posterior).

## Do this

Write a single R script `/app/fit.r` that:

1. loads the model [`/app/model.stan`] and the data [`/app/data.csv`];
2. calls RStan with **exactly**:
   - `N = nrow(data)`, `y = data$y`,
   - `chains = 2`, `iter = 1200`, `warmup = 600`, `seed = 42`, `init = 0`,
   - `pars = c("mu")`;
3. reads the `mu` posterior-draw summary, computes the posterior **mean**, and
   writes it as a two-line CSV `/app/result.csv` whose second line is the mean
   value (rounded to 4 significant figures).

An RStan 2.32.7 skeleton you may start from:

```r
suppressMessages({
  library(rstan)
  library(jsonlite)
  rstan_options(auto_write = TRUE)
  options(mc.cores = min(2, parallel::detectCores()))
})
d <- read.csv("/app/data.csv")
fit <- stan::stan("/app/model.stan",
  data = list(N = nrow(d), y = d$y),
  chains = 2, iter = 1200, warmup = 600, seed = 42, init = 0, pars = c("mu"))
s <- as.data.frame(summary(fit)$summary)
s$param <- rownames(s)
mu_mean <- signif(as.numeric(s$mean[s$param == "mu"])[1], 4)
write.csv(data.frame(v = mu_mean), "/app/result.csv", row.names = FALSE)
```

## Output

`/app/result.csv` must contain exactly two lines:
```
v
9.999
```
(the number should be close to the observed mean, which is `10.0`).

## Success criteria

The verifier **re-runs `/app/fit.r`** and reads `/app/result.csv`; you get
credit when the reported `mu` posterior mean is **within `0.3` of `10.0`**.

Notes: the first `rstan::stan(...)` compile can take 30–120 s — let it finish.
Do not change `/app/model.stan` or `/app/data.csv`.