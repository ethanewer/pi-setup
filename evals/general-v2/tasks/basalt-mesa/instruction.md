# Fit a parametric Bayesian network over the recovered sensor DAG

Watershed Analytics monitors river gauging stations. Each station logs several
continuous water-quality variables that are believed to influence each other
along an unknown **directed acyclic graph** (a tree). You must (1) recover the
tree structure from the data, and (2) fit a **linear-Gaussian parametric model**
under that structure so that data resampled from your fitted parameters
statistically matches the observed distribution.

## Environment

- Working directory: `/app`, containing:
  - `/app/obs.csv` — comma-separated observations (header row, ~3000 rows) of
    the network columns named in the DAG spec.
  - `/app/dag.json` — the DAG spec, a JSON object with keys:
    - `nodes`: all column names.
    - `network_columns`: the columns forming the network (same list here).
    - `root`: the unique declared **root** of the network.
    - `edge_count`: the exact number of edges (a tree: `len(nodes) - 1`).
- Python 3.12 with `numpy` is installed. No other third-party packages.
- **Do not modify `/app/obs.csv` or `/app/dag.json`.**

## Deliverables (all required)

1. **`/app/solve.py`** — a reusable solver with this exact CLI:
   ```
   python3 /app/solve.py <obs.csv> <dag.json> <outdir>
   ```
   It must read the data and DAG spec from the given paths (never hard-code the
   visible values) and write the three result files below into `<outdir>`.
   Print a line containing `SOLVER_OK` on success.

2. **`/app/recovered_edges.csv`**, **`/app/network_fit.csv`**,
   **`/app/root_fit.csv`** — the outputs of running your solver on the visible
   data with `<outdir>` = `/app`:
   ```
   python3 /app/solve.py /app/obs.csv /app/dag.json /app
   ```

The grader re-runs `/app/solve.py` on **hidden datasets** with different column
names, network sizes, topologies, and coefficient regimes, so everything must
be driven by the passed-in files only.

## Output schemas (exact)

`recovered_edges.csv`:
```
parent,child
temp,ph
...
```

`network_fit.csv` (one row per recovered edge, same order as
`recovered_edges.csv`):
```
parent,child,intercept,slope,sigma
temp,ph,-0.123456789,0.548652301,0.811223344
...
```

`root_fit.csv` (exactly one data row):
```
node,mu,sigma
temp,0.123456789,1.412300456
```

## Structure recovery (implement exactly)

- Compute the Pearson correlation matrix over the `network_columns`.
- Build the **maximum-|correlation| spanning tree** with Prim's algorithm,
  starting from the **first** node in `network_columns`: repeatedly add the
  pair `(i, j)` across the cut (already-included vs. remaining) with the
  largest `|corr(i, j)|`; break ties by the smallest lexicographic
  `(min(i,j), max(i,j))` **index pair** (indices are positions in
  `network_columns`). Stop after `edge_count = n - 1` edges.
- Orient every skeleton edge **away from `root`** (breadth-first from the root
  over the undirected skeleton).

## Parametric fit (implement exactly)

For each recovered edge `parent -> child`, using the observed columns:

- `slope = cov(parent, child) / var(parent)` with **population** moments
  (`ddof=0`).
- `intercept = mean(child) - slope * mean(parent)`.
- `residual = child - (intercept + slope * parent)`;
  `sigma = sqrt(mean(residual^2))` (population, denominator `n`).

For the root column: `mu = mean(root)`, `sigma = std(root)` (`ddof=0`).

Write all numbers with high precision (9 decimal places or more).

## Statistical acceptance (what the grader checks)

1. Your recovered edge set must match the reference recovery exactly.
2. Every fitted coefficient must match the reference fit within a tight
   relative tolerance (a lazy or inaccurate fit — e.g. wrong variance
   convention at small n, regression on the wrong axis, missing intercept —
   fails).
3. **KS resampling test.** The grader simulates a large synthetic dataset from
   *your* fitted parameters (root drawn from your root normal; each child drawn
   from your `intercept + slope * parent + N(0, sigma)` along the tree), then
   runs a two-sample Kolmogorov–Smirnov test of each simulated column against
   the corresponding observed column. If your coefficients or sigmas are
   inaccurate, the resampled distribution shifts off the reference and the KS
   test fails. All columns must pass with KS distance <= 0.035.

## Constraints

- Standard library + `numpy` only; no network access.
- The solver must not crash on any valid input following the schema above.
