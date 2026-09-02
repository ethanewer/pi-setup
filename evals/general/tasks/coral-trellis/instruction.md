# BeaconGrid mesh forensics: recover the propagation DAG

BeaconGrid operates a mesh of environmental gauges. A past incident rewired the
mesh, and all you have left is **telemetry**: synchronized samples from each
gauge. The propagation network among the gauges is a directed acyclic graph
(a tree), and you must recover **exactly** which directed edges existed from
the observed samples alone, using the forensic heuristics below.

You must build a **reusable** command-line solver. It will be re-run by the
grader on hidden telemetry sets (different gauges, different topologies,
different roots, different column orderings), so every step must be driven by
the input files — nothing about the visible fixture may be hard-coded.

## Environment

- Working directory: `/app`. It already contains the visible fixtures
  `/app/telemetry.csv` (comma-separated float samples **with a header row of
  column names**) and `/app/spec.json`.
- **Do not modify `/app/telemetry.csv` or `/app/spec.json`.**
- Python 3.12 is available as `python3`; use the standard library only (no
  third-party packages, no network).

## Deliverables (both required)

1. `/app/solver.py` — a runnable Python program with this interface:
   ```
   python3 /app/solver.py <data_csv> <spec_json> <outdir>
   ```
   It reads the telemetry CSV and the spec JSON given by the paths, recovers
   the directed edges with the heuristics below, and writes them to
   `<outdir>/recovered_edges.csv` (header `parent,child`, one directed edge
   per row). It must work on any telemetry/spec pair conforming to the
   contract below, and must exit with status 0.

2. `/app/recovered_edges.csv` — the edge list your program produces **when run
   on the provided fixtures**:
   ```
   python3 /app/solver.py /app/telemetry.csv /app/spec.json /app
   ```

## Spec format

`spec.json` is a JSON object with the keys:

- `"columns"`: the ordered list of column names forming the network (all of
  them appear as columns in the CSV header; the CSV may list them in a
  different order than the spec).
- `"root"`: the unique declared **root** (source) node of the DAG.
- `"edge_count"`: the exact number of directed edges (a tree over the
  columns, so always `len(columns) - 1`).

## Recovery heuristics (apply exactly, in this order)

1. **Correlation matrix.** Compute the pairwise **Pearson correlation**
   between every pair of columns over all sample rows.

2. **Fixed edge count (skeleton).** The skeleton is a tree with exactly
   `edge_count` edges. Build it as the **maximum-|r| spanning tree**: run
   Prim's algorithm starting from `columns[0]` (the first name in the spec's
   `columns` list); at each step add the edge between the already-connected
   set and the remaining nodes with the **largest |r|**, breaking any tie by
   choosing the pair with the smallest index pair `(i, j)` in the spec's
   `columns` order. Stop when every column is connected.

3. **Root constraint.** The node named by `"root"` is the unique source.
   Orient every skeleton edge **away from the root** (breadth-first over the
   tree from the root; a tree edge between a node and its BFS parent is
   directed parent → child).

4. **Child-analogy rule (ambiguity resolution).** Siblings in the tree must
   be conditionally independent given their shared parent. If any orientation
   of a skeleton edge still seems ambiguous after step 3, keep the
   orientation under which the child and each of its siblings are conditionally
   independent given the shared parent. (With a unique root and a tree
   skeleton this resolves every direction; never leave an edge undirected and
   never introduce a second source.)

The output must contain exactly the `edge_count` directed edges; **both the
skeleton and the directions matter** — a wrong parent/child order counts as a
wrong edge.

## Output format

`recovered_edges.csv` — header line exactly:

```
parent,child
```

then one row per directed edge, e.g. `m0,m1` means the edge `m0 -> m1`. Row
order is not checked, but the **set** of directed edges is compared exactly.

## Why the naive guesses fail

Hidden telemetry sets deliberately break shortcuts:

- the spec's `columns` order is **not** the topological order, and the root is
  often **not** `columns[0]` — orientation must come from the root constraint,
  not from column order;
- some non-adjacent pairs (grandparent/grandchild) correlate strongly — a
  greedy "connect highest pairs" scan that is not a proper spanning tree, or
  one that ignores the cut structure, produces a wrong skeleton;
- rows are plain floats with full precision; the true tree is recoverable with
  a clear margin at every Prim step when the algorithm is implemented as
  specified.

## Constraints

- The verifier runs your program **unchanged** on hidden inputs that follow
  the same contract; do not hard-code the visible fixtures or filenames.
- Standard library only; no network at build, run, or verify time.
- Do not modify `/app/telemetry.csv` or `/app/spec.json`.
