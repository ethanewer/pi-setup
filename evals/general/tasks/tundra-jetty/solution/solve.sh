#!/usr/bin/env bash
# RMLab / tundra-jetty oracle.
# Does the real work: authors every deliverable by running the analysis in R.
# Never reads /tests, never reads expected answers, never touches /logs.
set -euo pipefail

echo "[solve] installing reusable solver"
cp /solution/solver.R /app/solver.R
chmod +x /app/solver.R

echo "[solve] writing analysis.Rmd (R Markdown harness)"
cat > /app/analysis.Rmd <<'RMD'
---
title: "RMLab tundra-jetty coupling harness"
output: html_document
---

## Setup: load the object data and the DAG specification

```{r setup, warning=FALSE, message=FALSE}
suppressMessages(library(jsonlite))
df   <- read.csv("/app/obs.csv", stringsAsFactors = FALSE)
spec <- fromJSON("/app/dag.json")
cat("loaded", nrow(df), "rows;",
    "network nodes:", paste(spec$network_columns, collapse = ", "), "\n")
```

## Coupling-based structure recovery

Heuristics from the spec: fixed edge count (a spanning tree on the network
columns with exactly `edge_count` edges), root constraint (every edge is
directed away from the declared root), and the child-analogy rule for any
residual directional ambiguity (siblings must be conditionally independent
given their shared parent).

```{r recover, warning=FALSE}
M  <- as.matrix(df[, spec$network_columns])
cc <- abs(cor(M))
n  <- length(spec$network_columns)
# maximum-|correlation| spanning tree (Prim) -> skeleton
added <- 1L; skel <- list()
while (length(added) < n) {
  bw <- -Inf; bi <- NA; bj <- NA
  for (i in added) for (j in setdiff(seq_len(n), added))
    if (cc[i, j] > bw) { bw <- cc[i, j]; bi <- i; bj <- j }
  added <- c(added, bj); skel[[length(skel) + 1L]] <- c(bi, bj)
}
adj <- vector("list", n)
for (e in skel) { adj[[e[1]]] <- c(adj[[e[1]]], e[2]); adj[[e[2]]] <- c(adj[[e[2]]], e[1]) }
# root constraint: orient the whole tree away from the root
root  <- which(spec$network_columns == spec$root)
edges <- list(); q <- root; parent <- rep(NA_integer_, n); parent[root] <- 0L
while (length(q) > 0) {
  u <- q[1]; q <- q[-1]
  for (v in adj[[u]]) if (is.na(parent[v])) {
    parent[v] <- u
    edges[[length(edges) + 1L]] <- c(spec$network_columns[u], spec$network_columns[v])
    q <- c(q, v)
  }
}
rec <- data.frame(do.call(rbind, edges), stringsAsFactors = FALSE)
names(rec) <- c("parent", "child")
rec <- rec[order(rec$parent, rec$child), , drop = FALSE]
write.csv(rec, "/app/recovered_edges.csv", row.names = FALSE)
knitr::kable(rec)
```

## Parametric fit under the recovered DAG

```{r fit, warning=FALSE}
fitrows <- lapply(seq_len(nrow(rec)), function(i) {
  m <- lm(df[[rec$child[i]]] ~ df[[rec$parent[i]]])
  data.frame(parent = rec$parent[i], child = rec$child[i],
             coefficient = as.numeric(coef(m)[2]))
})
fitdf <- do.call(rbind, fitrows)
write.csv(fitdf, "/app/network_fit.csv", row.names = FALSE)
knitr::kable(fitdf)
```

## Average treatment effect with the adjustment set

```{r ate}
am <- lm(df[[spec$outcome_column]] ~ df[[spec$treatment_column]] + df[[spec$confounder_column]])
ate <- as.numeric(coef(am)[2])
writeLines(sprintf("%.6f", ate), "/app/ate.txt")
cat("ATE =", ate, "\n")
```

## Hierarchical beta-binomial with Jeffreys-type prior (rstan)

```{r stan, warning=FALSE, message=FALSE}
stan_code <- "
data {
  int<lower=0> G;            // number of groups
  int<lower=1> N[G];         // trials per group
  int<lower=0> K[G];         // successes per group
}
parameters {
  real<lower=0> alpha;
  real<lower=0> beta;
  vector<lower=0, upper=1>[G] theta;
}
model {
  // Jeffreys-type hyperprior over the (alpha,beta) pair
  target += -0.5*log(alpha) - 0.5*log(beta) - 0.5*log(alpha + beta);
  theta ~ beta(alpha, beta);
  for (g in 1:G) K[g] ~ binomial(N[g], theta[g]);
}
"
writeLines(stan_code, "/app/hierarchical_model.stan")
if (nzchar(Sys.getenv("RMLAB_STAN"))) {
  suppressMessages(library(rstan))
  Nv <- as.integer(table(df[[spec$group_column]]))
  Kv <- as.integer(by(df[[spec$trial_column]], df[[spec$group_column]], sum))
  sm  <- stan_model(model_code = stan_code)
  fit <- sampling(sm, data = list(G = spec$groups, N = Nv, K = Kv),
                  iter = 1600, warmup = 600, chains = 1, seed = 20240101,
                  refresh = 0, control = list(adapt_delta = 0.98, max_treedepth = 12))
  par <- extract(fit, permuted = TRUE)
  th  <- do.call(cbind, lapply(seq_len(spec$groups), function(g) par$theta[, g]))
  colnames(th) <- paste0("theta", seq_len(spec$groups))
  write.csv(th, "/app/posterior.csv", row.names = FALSE)
  cat("posterior rows:", nrow(th), "\n")
}
```
RMD

echo "[solve] writing analysis.ipynb (legacy nbformat, R kernel)"
python3 - <<'PY'
import json
nb = {
  "cells": [
    {"cell_type": "markdown", "metadata": {}, "source": ["# RMLab tundra-jetty harness"]},
    {"cell_type": "code", "execution_count": None, "metadata": {},
     "outputs": [], "source": ["df <- read.csv('/app/obs.csv', stringsAsFactors = FALSE)\nhead(df)"]},
    {"cell_type": "code", "execution_count": None, "metadata": {},
     "outputs": [], "source": ["library(jsonlite)\nspec <- fromJSON('/app/dag.json')\nprint(spec$nodes)"]},
    {"cell_type": "code", "execution_count": None, "metadata": {},
     "outputs": [], "source": ["cat('loaded', nrow(df), 'rows and DAG spec with', length(spec$nodes), 'nodes\\n')"]}
  ],
  "metadata": {
    "kernelspec": {"display_name": "R", "language": "R", "name": "ir"},
    "language_info": {"name": "R", "codemirror_mode": "r", "pygments_lexer": "r",
                      "mimetype": "text/x-r-source", "version": "4.4"}
  },
  "nbformat": 4, "nbformat_minor": 5
}
with open("/app/analysis.ipynb", "w") as f:
    json.dump(nb, f, indent=1)
PY

echo "[solve] running the full analysis in R (data + DAG -> all result files)"
cd /app
Rscript --vanilla /app/solver.R /app/obs.csv /app/dag.json /app full

echo "[solve] ORACLE_DONE"
for a in analysis.Rmd analysis.ipynb solver.R hierarchical_model.stan \
         recovered_edges.csv network_fit.csv ate.txt posterior.csv; do
  [ -s "/app/$a" ] && echo "  [ok] /app/$a ($(wc -l < /app/$a) lines)" || { echo "  [MISSING] /app/$a"; exit 1; }
done
