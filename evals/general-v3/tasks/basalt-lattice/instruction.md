# RelayGrid basalt-lattice: telemetry DAG recovery

You are on the **RelayGrid** signal-integrity team. A rack of sensors produced an
observational sample log, and the wiring diagram was lost. You must recover the
**directed acyclic graph (DAG)** that generated the data by applying a fixed,
fully specified structure-learning procedure to the observed samples — the
procedure is deterministic, so there is exactly one correct edge set.

## Environment

- Working directory: `/app`. It already contains:
  - `/app/samples.csv` — comma-separated observational samples (header row of
    column names, then one numeric row per sample).
  - `/app/spec.json` — the recovery spec:
    ```json
    {
      "network_columns": ["vbus", "clock", "temp", "hum", "press", "vib"],
      "root": "vbus",
      "edge_count": 5
    }
    ```
- Python 3.12 is available as `python3` (standard library only; no network).
- **Do not modify `/app/samples.csv` or `/app/spec.json`.**

## Deliverables (all three required)

1. **`/app/solver.py`** — a reusable Python program with this interface:
   ```
   python3 /app/solver.py <samples.csv> <spec.json> <edges_out.csv> <fit_out.csv>
   ```
   It must read the samples and spec given by the paths (never hard-code the
   visible values) and write the two CSV outputs described below.

2. **`/app/recovered_edges.csv`** — the edges output your solver produces when
   run on the provided `/app/samples.csv` and `/app/spec.json`.

3. **`/app/fit.csv`** — the fit output your solver produces on the same inputs.

The grader re-runs `/app/solver.py` on **hidden datasets** (different node
names, network sizes, roots, and correlation structures), so the procedure must
be implemented exactly and generically.

## The recovery procedure (implement exactly)

Let `cols = spec["network_columns"]` (this is the canonical node order, index 0
.. n-1), `root = spec["root"]`, and `edge_count = spec["edge_count"]`. All
floating-point comparisons below use a **tolerance of 1e-9** (two values count
as tied when they differ by at most 1e-9).

**Step 1 — pairwise correlations.** For every pair of columns compute the
ordinary Pearson correlation coefficient `r(i, j)` over all sample rows.

**Step 2 — maximum-|r| spanning tree (fixed edge count).** The skeleton is a
tree with exactly `edge_count = n - 1` edges, built greedily (Prim-style):

- Start with the set `included = {cols[0]}` (the first column in
  `network_columns` order).
- Repeat until every node is included: consider all candidate edges
  `(u, v)` with `u ∈ included`, `v ∉ included`; let `M` be the maximum `|r(u,v)|
  ` over all candidates. The **tied candidates** are those with `|r(u,v)| ≥ M −
  1e-9`. Among the tied candidates, resolve as follows:
  - **(a) Child preference:** if the tied candidates attach *different* new
    nodes `v`, prefer the candidate whose `v` comes earliest in
    `network_columns` order (break any remaining tie by the earliest `u`).
  - **(b) Analogical child rule (ambiguous direction):** if all tied
    candidates attach the *same* node `v` to *different* parents, the direction
    is genuinely ambiguous. For each tied candidate parent `p` (with the other
    tied candidate parent `q`) compute the partial correlation of the child
    with the parent controlling for the other candidate:
    ```
    pc(v, p | q) = (r(v,p) − r(v,q)·r(p,q)) / sqrt((1 − r(v,q)²)·(1 − r(p,q)²))
    ```
    Attach `v` to the parent with the **largest** partial correlation (values
    within 1e-9 tie → earliest parent in `network_columns` order). If any
    partial correlation is **undefined** (e.g. `r(p,q) = ±1` zeroes the
    denominator), skip the partial-correlation comparison and attach `v` to the
    earliest tied parent in `network_columns` order.
- Add exactly one edge per step.

**Step 3 — root constraint.** `root` is the unique source of the DAG. Orient
every skeleton edge away from the root by breadth-first traversal from `root`
over the tree (each tree edge is directed parent → child).

**Step 4 — outputs.**

`<edges_out.csv>`:
```
parent,child
<parent>,<child>
...
```
one row per directed edge (a row `vbus,clock` means the edge `vbus -> clock`),
rows sorted by (parent index, child index) in `network_columns` order. The file
must contain exactly `edge_count` data rows.

`<fit_out.csv>`:
```
parent,child,slope
<parent>,<child>,<slope>
...
```
same rows in the same order, where `slope` is the ordinary least-squares slope
of regressing `child ~ parent` (i.e. `cov(parent,child)/var(parent)`), written
with exactly **6 decimal places** (`%.6f`).

## Edge cases the grader probes

- A **near-tie** between two candidate edges whose `|r|` values differ by more
  than the tolerance: the larger one must win (do not over-apply the tolerance).
- An **exact tie** (identical `|r|` values to machine precision): the tie-break
  rules (a)/(b) above decide; getting them backwards changes the edge set.
- The **root is not the first column** of `network_columns`; orientation still
  flows away from `root`.
- **Negative correlations**: the skeleton maximizes `|r|`, so a strong negative
  correlation is preferred over a weaker positive one.

## Constraints

- Standard library only; no network access at build, solve, or verify time.
- Do not modify `/app/samples.csv` or `/app/spec.json`.
- The verifier runs `/app/solver.py` unchanged on hidden inputs that follow the
  same format, so never hard-code column names, node counts, or results.
