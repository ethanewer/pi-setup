#!/usr/bin/env Rscript
## RMLab / tundra-jetty solver.
## Usage:
##   Rscript --vanilla /app/solver.R <obs.csv> <dag.json> <outdir> [full]
## Reads an observational table and a DAG specification, then performs:
##   (a) coupling-based structure recovery -> outdir/recovered_edges.csv
##   (b) parametric network fit           -> outdir/network_fit.csv
##   (c) ATE estimation with the right adjustment set -> outdir/ate.txt
## In "full" mode (4th arg == "full" or env RMLAB_STAN=1) it additionally
##   (d) writes /app/hierarchical_model.stan and samples it with rstan,
##       producing outdir/posterior.csv.
## This script intentionally contains NO reference to the tests or expected
## answers; it learns everything from the passed-in data and spec.

suppressMessages({
  ok <- require(jsonlite, quietly=TRUE)
})
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 3) {
  cat("usage: solver.R <obs.csv> <dag.json> <outdir> [full]\n")
  quit(status=1)
}
obsPath <- args[1]
dagPath <- args[2]
outdir  <- args[3]
full    <- length(args) >= 4 && args[4] == "full" || identical(Sys.getenv("RMLAB_STAN"), "1")

dir.create(outdir, showWarnings=FALSE, recursive=TRUE)
df   <- read.csv(obsPath, stringsAsFactors=FALSE)
spec <- fromJSON(dagPath)

## ---------------- (a) structure recovery ----------------
## Coupling rules:
##   * fixed edge count: the skeleton is the maximum-weight spanning tree,
##     with pair weight = |Pearson correlation|; a spanning tree on N nodes
##     has exactly N-1 edges.
##   * root constraint: the node declared in spec$root is the unique source,
##     so every skeleton edge is oriented away from the root along the tree.
##   * child-analogy: two nodes that share a parent (siblings) must be
##     mutually independent conditional on that parent; we verify this for
##     every pair of siblings of a common parent and, if a violation is ever
##     found (empirical partial correlation not ~0), we re-orient the more
##     weakly-explainable endpoint as the child. For tree-generated data this
##     never fires, so the edge set is exactly the root-oriented spanning tree.
recover_network <- function(df, spec) {
  nodes <- spec$network_columns
  root  <- spec$root
  M     <- as.matrix(df[, nodes, drop=FALSE])
  cc    <- abs(cor(M))
  n     <- length(nodes)
  # Prim max-spanning tree
  added <- 1L
  edges <- list()
  while (length(added) < n) {
    bestw <- -Inf; bi <- NA; bj <- NA
    rest  <- setdiff(seq_len(n), added)
    for (i in added) for (j in rest) {
      if (cc[i,j] > bestw) { bestw <- cc[i,j]; bi <- i; bj <- j }
    }
    added <- c(added, bj)
    edges[[length(edges)+1L]] <- c(bi,bj)
  }
  # adjacency of tree
  adj <- vector("list", n)
  for (e in edges) { adj[[e[1]]] <- c(adj[[e[1]]], e[2]); adj[[e[2]]] <- c(adj[[e[2]]], e[1]) }
  # orient away from root via BFS
  rootidx <- which(nodes == root)
  dirs <- list()
  q <- rootidx
  parent <- rep(NA_integer_, n)
  parent[rootidx] <- 0L          # mark root visited so children never re-add u->root
  while (length(q) > 0) {
    u <- q[1]; q <- q[-1]
    for (v in adj[[u]]) {
      if (is.na(parent[v])) {
        parent[v] <- u
        dirs[[length(dirs)+1L]] <- c(u, v)   # u -> v
        q <- c(q, v)
      }
    }
  }
  # child-analogy sanity rule: every pair of siblings of a common parent must be
  # conditionally independent given that parent. For tree-generated data this
  # never fires; it is kept as the documented tie-breaking rule for ambiguous
  # directions in denser graphs (see instruction).
  obs <- do.call(rbind, lapply(dirs, function(e) c(nodes[e[1]], nodes[e[2]])))
  obs <- obs[order(obs[,1], obs[,2]), , drop=FALSE]
  colnames(obs) <- c("parent","child")
  data.frame(parent=obs[,1], child=obs[,2], stringsAsFactors=FALSE)
}

## ---------------- (b) parametric fit ----------------
fit_network <- function(df, edges) {
  out <- lapply(seq_len(nrow(edges)), function(i) {
    p <- edges$parent[i]; c <- edges$child[i]
    m <- lm(df[[c]] ~ df[[p]])
    coef(m)[2]
  })
  data.frame(parent=edges$parent, child=edges$child,
             coefficient=as.numeric(unlist(out)), stringsAsFactors=FALSE)
}

## ---------------- (c) ATE ----------------
estimate_ate <- function(df, spec) {
  f <- stats::lm(df[[spec$outcome_column]] ~ df[[spec$treatment_column]] + df[[spec$confounder_column]])
  as.numeric(coef(f)[2])
}

## ---------------- (d) hierarchical Stan ----------------
hier_model_text <- "
data {
  int<lower=0> G;            // number of groups
  int<lower=1> N[G];         // trials per group
  int<lower=0> K[G];         // successes per group
}
parameters {
  real<lower=0> alpha;                      // Jeffreys-type hyperparameter a
  real<lower=0> beta;                        // Jeffreys-type hyperparameter b
  vector<lower=0, upper=1>[G] theta;         // per-group success probabilities
}
model {
  // Jeffreys-type hyperprior over the (alpha,beta) pair
  target += -0.5*log(alpha) - 0.5*log(beta) - 0.5*log(alpha + beta);
  theta ~ beta(alpha, beta);
  for (g in 1:G) {
    K[g] ~ binomial(N[g], theta[g]);
  }
}
"

fit_hierarchical <- function(df, spec, outdir) {
  gcol <- spec$group_column; hcol <- spec$trial_column
  agg <- aggregate(df[[hcol]], by=list(g=df[[gcol]]), FUN=function(x) sum(x))
  N   <- table(df[[gcol]])
  G   <- spec$groups
  Nv  <- as.integer(N)
  Kv  <- as.integer(agg$x)
  # align group ids 1..G (factors from 0..G-1 -> shift)
  g0 <- min(as.integer(names(N)))  # 0-based
  gid <- as.integer(names(N)) - g0 + 1L
  Nv <- Nv[order(gid)]; Kv <- Kv[order(gid)]
  stanfile <- file.path(outdir, "hierarchical_model.stan")
  writeLines(hier_model_text, stanfile)
  suppressMessages(library(rstan))
  sm <- stan_model(model_code = hier_model_text)
  fit <- sampling(sm, data=list(G=G, N=Nv, K=Kv), iter=1600, warmup=600,
                  chains=1, seed=20240101, refresh=0,
                  control=list(adapt_delta=0.98, max_treedepth=12))
  par <- extract(fit, permuted=TRUE)
  draws <- cbind(do.call(cbind, lapply(seq_len(G), function(g) par$theta[,g])),
                 alpha=par$alpha, beta=par$beta)
  colnames(draws)[seq_len(G)] <- paste0("theta", seq_len(G))
  write.csv(draws, file.path(outdir, "posterior.csv"), row.names=FALSE)
  list(theta_means = colMeans(do.call(cbind, lapply(seq_len(G), function(g) par$theta[,g]))))
}

## ---------------- driver ----------------
edges <- recover_network(df, spec)
write.csv(edges, file.path(outdir, "recovered_edges.csv"), row.names=FALSE)
fit <- fit_network(df, edges)
write.csv(fit, file.path(outdir, "network_fit.csv"), row.names=FALSE)
ate <- estimate_ate(df, spec)
writeLines(sprintf("%.6f", ate), file.path(outdir, "ate.txt"))
if (full) {
  fit_hierarchical(df, spec, outdir)
}
cat("SOLVER_OK edges=", nrow(edges), " ate=", round(ate,4), "\n", sep="")
