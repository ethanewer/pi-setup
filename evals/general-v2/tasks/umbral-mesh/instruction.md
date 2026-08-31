# GridSense fault-propagation DAG recovery

GridSense ships diagnostics for industrial sensor grids. A fault propagates
through the grid as a **directed acyclic graph (DAG)** over sensor channels, but
only observational telemetry survives. You must recover the directed edge set
from the samples using a **fixed, deterministic heuristic** (specified below) and
package it as a reusable command-line program. The heuristic is guaranteed to
yield a **unique** edge set for every input that follows this contract.

## Environment

- Working directory: `/app`. It already contains the visible fixtures
  `/app/telemetry.csv` and `/app/spec.json`. Python 3.12 is available as
  `python3`; use the **standard library only** (no third-party packages).
- **Do not modify `/app/telemetry.csv` or `/app/spec.json`.**

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <telemetry_csv> <spec_json> <output_csv>
   ```
   It reads the telemetry and spec given by the paths (never hard-code the
   visible values) and writes the recovered directed edges to `<output_csv>`.

2. `/app/recovered_edges.csv` — the edge set your program produces **when run on
   the provided `/app/telemetry.csv` and `/app/spec.json`**:
   ```
   python3 /app/solve.py /app/telemetry.csv /app/spec.json /app/recovered_edges.csv
   ```

The grader re-runs `/app/solve.py` on **hidden** telemetry/spec pairs (different
column counts, roots, distractor columns, and hints), so the implementation must
be fully general.

## Input format

`<telemetry_csv>` is comma-separated with a one-line header, then one row of
numeric samples per line. The first header field is `step` (a row counter); the
remaining fields are named sample columns. The file may contain **distractor
columns** that are not part of the network.

`<spec_json>` is a JSON object with exactly these keys:

- `"columns"` — the ordered list of network column names (the DAG nodes), e.g.
  `["c0", "c1", "c2"]`. Only these columns participate; distractors are ignored.
- `"root"` — the unique **root node** of the target DAG.
- `"edge_count"` — the exact number of directed edges (always `len(columns) - 1`;
  the skeleton is a tree).
- `"directed_hints"` — a list of `[parent, child]` pairs of domain-knowledge
  direction constraints (may be empty).

## The recovery heuristic (implement exactly, in this order)

1. **Read samples.** Load only the columns named in `"columns"`, in that order;
   index them `0..n-1` by that order.
2. **Pairwise correlation.** For every unordered pair `(i, j)` with `i < j`
   compute the Pearson correlation coefficient `r(i, j)` of the two sample
   vectors (standard formula: `sum((x-mx)(y-my)) / sqrt(sum((x-mx)^2) *
   sum((y-my)^2))`).
3. **Fixed edge count (maximum-|r| spanning tree).** Sort all candidate pairs
   ascending by the key `(-abs(r), i, j)` (i.e. strongest |correlation| first;
   ties broken by the smaller then larger column index). Scan with a
   union-find, accepting a pair only when it joins two different components;
   stop once `edge_count` pairs are accepted. The accepted pairs are the
   **skeleton**.
4. **Root constraint.** The node named by `"root"` is the unique source. Orient
   every skeleton edge away from the root: run a breadth-first traversal from
   the root over the skeleton (visiting each node's skeleton neighbours in
   ascending column-index order); each tree edge is directed
   `discovered -> discoverer's child`, i.e. `parent -> child` when the child is
   first reached.
5. **Ambiguity resolution (hint flips).** For each `[p, c]` in
   `"directed_hints"`: if both `p` and `c` are network columns **and** the
   skeleton contains the edge between them **and** the current orientation is
   `c -> p`, flip that edge to `p -> c`. Hints whose pair is not a skeleton edge
   are ignored. (This is the only step that may override step 4.)

Steps 1–5 always produce exactly one edge set for a conforming input.

## Output format

`<output_csv>` (and `/app/recovered_edges.csv`) must be a comma-separated file
with the header line

```
parent,child
```

followed by one row `parent,child` per recovered directed edge, **sorted
ascending** by the tuple `(parent, child)` compared as plain strings. There must
be exactly `edge_count` rows. A row `m0,m1` means the edge `m0 -> m1`.

## Edge cases the hidden inputs probe

- Different network sizes (3 to 8 nodes) and a root that is **not** the
  generative source of the data — the root constraint in step 4 always wins.
- Distractor columns that correlate weakly with the network; they must be
  excluded because they are not in `"columns"`.
- Hints that **agree** with step 4 (no change), hints that **conflict** (the
  edge must be flipped), and hints that reference a non-skeleton pair or a
  non-network column (ignored).
- Few rows (a few hundred) — do not assume any particular row count.

## Constraints

- Standard library only; no network access.
- The verifier runs `/app/solve.py` unchanged on hidden fixtures; do not
  special-case the visible data or filenames.
- Do not modify the supplied fixtures.
