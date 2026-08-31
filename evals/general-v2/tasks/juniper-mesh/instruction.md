# Hydronet gauge network: structure discovery + parametric Bayesian fit

You are modeling a **hydrology gauge network**. Six sensors report continuous
readings; the gauge variables follow a linear-Gaussian directed acyclic graph
(Bayesian network). You must recover the DAG's structure from the data, fit the
**parametric conditional model** of every gauge under the recovered DAG, and
then run **ancestral sampling** to synthesize a new data set whose statistics
track the fitted model.

Everything is under `/app`:

- `/app/sensors.csv` — the observations (header row, ~6000 rows, plain floats).
- `/app/network.json` — the network spec:
  ```json
  {"columns": [...], "order": [...], "edge_threshold": 0.30,
   "samples": 20000, "seed": 811}
  ```
  - `columns`: all variable names.
  - `order`: a **topological order** of the variables (any edge goes from an
    earlier to a later entry).
  - `edge_threshold`: the discovery threshold (see rule below).
  - `samples` / `seed`: size and RNG seed for the synthesis stage.

Python 3.12 is available; **standard library only** (no numpy/scipy).

**Do not modify `/app/sensors.csv` or `/app/network.json`.**

## Deliverables

1. `/app/bnfit.py` — a reusable solver with this exact CLI:
   ```
   python3 /app/bnfit.py <sensors.csv> <network.json> <outdir>
   ```
   It must read the data and spec from the given paths (never hard-code the
   visible values), create `<outdir>` if needed, and write the three outputs
   below into it. It must print a line containing `BNFIT_OK` on success.
2. `/app/edges.csv`, `/app/fit.json`, `/app/synthetic.csv` — the outputs of
   running your solver on `/app/sensors.csv` and `/app/network.json` with
   outdir `/app`.

## Stage 1 — structure discovery (exact rule)

For every ordered pair `(p, c)` where `p` **precedes** `c` in `order`, compute
the Pearson correlation `r(p, c)` over the rows. Add the directed edge
`p -> c` **iff** `|r(p, c)| >= edge_threshold`. No other edges exist.

## Stage 2 — parametric fit under the discovered DAG

For every variable `c` in `order`, let `parents(c)` be the discovered parents
(kept in `order` sequence). Fit a **multiple ordinary least squares**
regression of `c` on `parents(c)` plus an intercept:

- one **coefficient per discovered parent** (the partial slope in the joint
  regression — not the pairwise slope),
- an **intercept**,
- a **residual std** = population standard deviation (`ddof=0`) of the OLS
  residuals.

For a **root** (no discovered parents): `intercept` = the sample mean of the
column, `resid_std` = the population std (`ddof=0`) of the column, and no
coefficients.

## Stage 3 — ancestral sampling

Generate exactly `samples` synthetic rows. Use a fresh
`random.Random(seed)` with `seed` taken from the spec. For each row, walk the
variables **in the spec's `order`**: sample each variable as

```
value = intercept + sum(coef[parent] * value[parent]) + gauss(0, resid_std)
```

using the fitted parameters from Stage 2 (roots use their intercept directly).

## Output formats (exact)

`edges.csv` — header `parent,child`, one row per discovered edge, sorted by
(child position in `order`, then parent position in `order`). Example row:
`v0,v1`.

`fit.json` — one key per variable (in `order`), each mapping to:

```json
{"intercept": <float>, "resid_std": <float>, "coefficients": {"<parent>": <float>}}
```

(`coefficients` is `{}` for roots.)

`synthetic.csv` — header is the variable list in the spec's `order`, then
exactly `samples` rows of plain floats.

The solver must be deterministic: running it twice on the same inputs with the
same outdir contents must produce byte-identical outputs.

## How this is graded

The verifier re-runs `/app/bnfit.py` unchanged on the visible inputs **and on
hidden data sets** with different variables, topological orders, thresholds,
sample sizes and seeds, and checks that:

- the discovered edge set matches the rule applied to the data,
- the fitted intercepts, per-parent coefficients and residual stds match the
  exact OLS fit under the discovered edges,
- each synthetic column passes a two-sample Kolmogorov–Smirnov test against the
  reference distribution of the true generating process (KS statistic <= 0.04),
- each discovered edge's parent/child correlation is reproduced in the
  synthetic data (within 0.08 of the data correlation),
- repeated runs are byte-identical.

Coefficients that are sloppy (pairwise slopes, wrong intercepts, inflated
residuals) or sampling that ignores the fitted conditionals will shift the
synthetic distributions off the reference and fail.

## Constraints

- Standard library only; no network access.
- All numeric outputs are plain floats (6-decimal CSV formatting is fine).
- Do not fabricate outputs without running your solver.
