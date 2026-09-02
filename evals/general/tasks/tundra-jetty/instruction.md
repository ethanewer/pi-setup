# RMLab tundra-jetty: Bayesian causal harness in R

You are analyzing an observational study packaged as an **RMLab harness**. All
fixtures live in `/app` inside a Docker container that already has a full R
runtime installed:

- R (4.x) with the **rstan** package installed and loadable, plus `jsonlite`,
  `knitr`, and `IRkernel`.
- Data file: `/app/obs.csv` (comma-separated, ~12,000 rows, header included).
- Model specification: `/app/dag.json` (JSON).
- Working directory: `/app`.

## 1. Data and DAG specification

`/app/obs.csv` has the following columns:

| column | meaning |
|---|---|
| `m0`..`m4` | observed continuous variables that form an unknown **directed acyclic graph** (a tree structure) |
| `conf` | a measured confounder of the treatment/outcome pair |
| `treat` | the treatment indicator (0/1) |
| `y` | the continuous outcome |
| `group` | group id (0..G-1) for a hierarchical beta-binomial study |
| `hit` | per-row binary success indicator (0/1) for that trial |

`/app/dag.json` is a JSON object with these keys:

- `nodes`: all node names.
- `network_columns`: the subset of columns forming the network to be recovered
  (the `m*` columns).
- `root`: the unique declared **root node** of the network.
- `edge_count`: the exact number of edges in the target DAG.
- `treatment_column`, `outcome_column`, `confounder_column`: column names used
  for the treatment-effect stage.
- `group_column`, `trial_column`, `groups`: column names / group count used for
  the hierarchical stage.

**Do not modify `/app/obs.csv` or `/app/dag.json`.**

## 2. Deliverables (build all of them)

Produce, and leave under `/app`:

1. **`/app/solver.R`** — an executable (`#!/usr/bin/env Rscript`) **reusable**
   solver. CLI:

   ```
   Rscript /app/solver.R <obs.csv> <dag.json> <outdir> [full]
   ```

   It must read the data and DAG spec given by the paths (NOT hardcode the
   visible values), and write:
   - `<outdir>/recovered_edges.csv` — recovered directed DAG edges, header
     `parent,child`, one edge per row.
   - `<outdir>/network_fit.csv` — parametric fit under the recovered DAG,
     header `parent,child,coefficient`, where `coefficient` is the slope of
     `lm(child ~ parent)` for each recovered edge.
   - `<outdir>/ate.txt` — the estimated average treatment effect as a single
     number with **6 decimal places**.
   - In `full` mode additionally:
     - `<outdir>/hierarchical_model.stan` — the Stan model source (see §4), and
     - `<outdir>/posterior.csv` — posterior draws from that model (see §4).

   On success print a line containing `SOLVER_OK`.

   **The grader will re-run `/app/solver.R` on additional (hidden) datasets** —
   different DAG topologies, different network sizes, group counts, and effect
   strengths — so the recovery, fit, and ATE logic must be fully generic and
   driven only by the passed-in data and the keys in the DAG spec.

2. **`/app/analysis.Rmd`** — a real R Markdown document (YAML header, ` ```{r} `
   code chunks) whose chunks load `/app/obs.csv` and `/app/dag.json` and run the
   structure recovery, network fit, and ATE estimation described below.

3. **`/app/analysis.ipynb`** — a **legacy nbformat-4 notebook** whose metadata
   declares an **R kernel** (`kernelspec` name `ir`, `language` `R`, plus an
   `r` `language_info`) and whose code cells actually load `/app/obs.csv` and
   `/app/dag.json`.

4. **`/app/hierarchical_model.stan`** — the exact Stan program you sample from
   (see §4).

5. **`/app/recovered_edges.csv`**, **`/app/network_fit.csv`**,
   **`/app/ate.txt`**, **`/app/posterior.csv`** — the results of running your
   solver (in `full` mode) on the `/app` data itself, with the exact schemas
   above.

## 3. Structure recovery and causal estimation

**Structure recovery (coupling heuristics).** Recover the directed network from
the observed `network_columns` using exactly these rules:

- *Fixed edge count:* the skeleton is a **tree** with exactly `edge_count`
  edges — form it as the **maximum-|Pearson-correlation| spanning tree** over
  the pairwise correlation matrix of the network columns (Prim: repeatedly add
  the pair `(i, j)` across the cut between the already-included and remaining
  nodes that has the largest |correlation|, until every node is connected;
  exactly `edge_count = n-1` edges for `n` nodes).
- *Root constraint:* the node named by `root` in the spec is the **unique
  source**. Orient every skeleton edge **away from the root** (breadth-first
  from the root over the tree).
- *Child-analogy rule:* if two nodes share a parent (siblings), they must be
  conditionally independent given that parent. When a directional choice is
  genuinely ambiguous, keep whichever orientation satisfies the sibling
  conditional-independence check for their shared parent.

The output `recovered_edges.csv` must contain exactly the directed edges
(`parent` is the source, `child` the target), e.g. a row `m0,m1` means the edge
`m0 -> m1`. Orientations matter.

**Parametric fit.** For each recovered edge `parent -> child`, regress
`child ~ parent` with ordinary least squares and record the slope coefficient.

**Average treatment effect.** Fit the outcome model
`outcome ~ treatment + confounder` (the adjustment set you need is exactly the
`confounder_column` in the spec) and report the treatment coefficient as the
ATE, written with six decimals.

## 4. Hierarchical beta-binomial model with rstan

You must author a **Stan** program encoding:

- a **hierarchical beta-binomial** model: for each group `g` in `1..G` (the
  spec's `groups`), `K[g] ~ binomial(N[g], theta[g])` with `theta[g] ~
  beta(alpha, beta)` (a shared beta group prior), and
- a **Jeffreys-type hyper-prior over the `(alpha, beta)` pair**, e.g.

  ```
  target += -0.5*log(alpha) - 0.5*log(beta) - 0.5*log(alpha + beta);
  ```

- `N[g]` = number of trials in group `g`, `K[g]` = successes in group `g`
  (count `hit` per group from `/app/obs.csv`).

The model must **parse without error and sample successfully** (the rstan
`stan_model` + `sampling` steps must run to completion in this session). Save
the source to both `/app/hierarchical_model.stan` and (via `full` mode)
`<outdir>/hierarchical_model.stan`. Run enough iterations to get a usable
posterior (e.g. `iter ≈ 1600`, `warmup ≈ 600`, one or more chains) and write
`posterior.csv` with **one row per posterior draw** and columns
`theta1, theta2, ..., thetaG, alpha, beta` (at least a few hundred rows).

## 5. Requirements / gotchas

- `/app/solver.R` must be executable and must rely only on its CLI arguments —
  never on the current directory or on the visible data by name.
- `library(rstan)` must load without error; rstan compiles the Stan model at
  runtime with the system C++ toolchain, so give the sampling step a bounded
  but sufficient iteration count (runtime is limited).
- Every CSV you write must have the exact headers listed above and no
  row-name column. `ate.txt` must contain only the number and a newline.
- The analysis must genuinely run in R (code paths must execute), including the
  sampling step for the `/app` data.
- Do not modify the fixtures; do not add network calls.

## 6. Self-check

Run:

```
cd /app
Rscript /app/solver.R /app/obs.csv /app/dag.json /app full
```

and confirm you see `SOLVER_OK`, that `/app/ate.txt` contains six decimals, that
`/app/posterior.csv` has header `theta1,...,thetaG,alpha,beta` and several
hundred rows, that `/app/recovered_edges.csv` has exactly `edge_count` directed
rows, and that `/app/analysis.Rmd` and `/app/analysis.ipynb` load the fixtures.
