# River Ferry — NSGA-II multi-objective optimizer

You are implementing a small **multi-objective evolutionary optimizer**
(NSGA-II: fast non-dominated sorting, crowding distance, elitist archive,
exact hypervolume) as a deterministic Python CLI. The container provides
two problem families with documented closed-form Pareto fronts; your job is
the **optimizer**, not the problems.

Your single deliverable is:

- `/app/nsga.py` — CLI: `python3 nsga.py <params.json> <result.json>`

Everything you need is already installed: only the **Python 3.12 standard
library** may be used (no numpy, no scipy, no network, no third-party
packages). The run must be **fully deterministic**: one `random.Random(seed)`
stream, no wall-clock or hash-based randomness anywhere.

## Environment

- `/app/problems/biobj.py` — the problem definitions. Read instances and
  evaluate solutions through it (recommended):
  ```python
  import sys
  sys.path.insert(0, "/app/problems")
  import biobj
  prob = biobj.instance(params["problem"], params["seed"])   # instance dict
  objs = biobj.evaluate(prob, solution)                      # objective tuple
  ```
  You may instead reimplement the formulas below yourself, but the grader
  recomputes objectives from your encodings either way.
- `/app/params.json` — a visible parameter file you can run right away.

## Problems (all objectives MINIMIZED; smaller is better)

| id | encoding | objectives `[f1, ...]` | reference point `R` |
|----|----------|------------------------|---------------------|
| `knapsack` | bitstring `s[0..n-1]`, `s[i] in {0,1}` | `[-total_value, total_weight]` | `[0, capacity]` |
| `saddle` | floats `x[0..m-1]` in `[0,1]` | `[x0, g·(1 − (x0/g)²)]` | `[1, 1 + 3(m−1)/16]` |
| `triplane` | floats `x[0..m-1]` in `[0,1]` | `[x0, x1, g − x0² − x1²]` | `[1, 1, 1 + 3(m−1)/16]` |

with `g = 1 + 0.75·Σ (x_i − 0.5)²` over the *tail* variables (indices ≥ 1 for
`saddle`, ≥ 2 for `triplane`). Instance sizes are seed-derived (read them
from the instance dict): `knapsack n = 20 + 4·(seed % 9)`, `saddle
m = 4 + (seed % 3)`, `triplane m = 5 + (seed % 3)`.

Feasibility: a solution must have the exact required length; knapsack bits
must be 0/1 and the selected weight ≤ capacity; continuous variables must
all lie in `[0,1]`. The instance dict also carries `values`, `weights`,
`capacity` (knapsack) and the `reference` point.

**Closed-form Pareto fronts** (documented; the grader measures against them):

- `knapsack`: no closed form — front is instance-specific (see grading).
- `saddle`: the front is exactly `f2 = 1 − f1²` for `f1 ∈ [0,1]`, attained
  iff every tail variable equals `0.5`. Every feasible point satisfies
  `f1² + f2 ≥ 1`, with equality exactly on the front.
- `triplane`: the front is the surface `f3 = 1 − f1² − f2²` over
  `(f1, f2) ∈ [0,1]²` (note: `f3` may be negative near `f1=f2=1`). Every
  feasible point satisfies `f1² + f2² + f3 ≥ 1`, with equality exactly on
  the front — the **front property**.

## params.json

```json
{ "problem": "knapsack"|"saddle"|"triplane", "pop": 60, "generations": 80, "seed": 20240407 }
```
`pop ≥ 2`, `generations ≥ 1`, `seed` any int. Unknown extra keys must be
tolerated and ignored.

## CLI contract

`python3 nsga.py <params.json> <result.json>` reads the params, runs the
optimizer, writes result.json and exits `0`. Exit `1` on any error (missing
file, malformed params, crash). Exit `2` on a usage error (wrong argument
count; print `usage: python3 nsga.py <params.json> <result.json>` to
stderr). No stdout output required (stderr for errors only).

## NSGA-II scheme (follow this; tie-breaks are part of the contract)

Use exactly one `random.Random(seed)` stream. Draw order (documented):
(1) initialize all `pop` individuals; then per generation, in order:
(2) the `pop` binary tournaments, (3) each pair's crossover draws,
(4) every gene's mutation draws — in the order your code visits them.

1. **Initialization**: knapsack — uniform random bitstrings; continuous —
   uniform points in `[0,1]^m`. For knapsack, repair as below.
2. **Evaluation** via biobj (`evaluate`).
3. **Fast non-dominated sorting** (standard `n_p`/`S_p` bookkeeping) of the
   current population. Tie-break: indices inside one rank are ordered by
   objective tuple, then index.
4. **Crowding distance** per rank: for each objective, sort by that
   objective; boundary individuals get a large finite sentinel; interior
   distance is the normalized interval span summed over objectives. Zero
   spread contributes 0.
5. **Binary tournament selection** (size 2, distinct indices): lower rank
   wins; equal rank → larger crowding distance; still tied → smaller index.
6. **Crossover** (probability 0.9, else children are parent clones):
   knapsack — single-point crossover at a random cut in `[1, n)`; continuous
   — uniform per-gene swap (each gene taken from parent 1 or 2 with
   probability ½).
7. **Mutation**: knapsack — per-gene bit-flip with probability `1/n`;
   continuous — per-gene uniform `±0.2` perturbation (clamped to `[0,1]`)
   with probability `1/(2n)`.
8. **Feasibility repair** (knapsack only): while weight > capacity, drop
   the selected item with the smallest value/weight ratio (ties: smallest
   index). Applied after initialization, crossover and mutation, before
   evaluation.
9. **Elitist survival**: merge parents and offspring (2·pop), non-dominated
   sort the merged set, fill the next population rank by rank; if a rank
   overflows, keep its members by **descending crowding distance** (ties:
   smaller index).
10. **External elitist archive**: after each generation, union the current
    population's rank-0 members into an archive, drop any archive member
    that is now dominated (or an exact objective duplicate), and when the
    archive exceeds `6·pop` members, truncate by descending crowding
    distance (ties: smaller index).

The **final front** reported in result.json is the non-dominated archive
(or the final population's rank 0 — both are acceptable), deduplicated by
exact objective tuple.

## result.json (exact schema)

```json
{
  "algorithm": "nsga2",
  "problem": "<problem id>",
  "params": { "problem": "...", "pop": N, "generations": G, "seed": S },
  "reference": [r1, r2, ...],
  "front": [
    { "solution": [enc...], "objectives": [f1, ...], "crowding_distance": 1.234 },
    ...
  ],
  "hypervolume": 123.456
}
```

- `front` entries sorted in **canonical order**: ascending by objective
  tuple (lexicographic, `f1` first). At least 5 entries for a real run.
- No two entries may share an identical objective tuple (dedupe, keeping the
  first in canonical order).
- `crowding_distance`: the point's crowding distance on the final front
  (finite, `≥ 0`; boundary sentinel allowed).
- `hypervolume`: the **exact** (analytic, deterministic — no Monte Carlo)
  hypervolume of the union of boxes `[f_i, R]` for every front point, w.r.t.
  the documented `reference` point (which must equal the one in the instance
  dict). 2 and 3 objectives.
- `params` must echo the input values exactly; `reference` must equal the
  instance reference (within `1e-6` absolute per component).

**Hypervolume definition**: for minimization objectives the dominated box of
a point `p` is `[p1,R1] × [p2,R2] (× [p3,R3])`; the hypervolume is the
measure of the **union** of these boxes, computed exactly.

## How the grader probes your deliverable (hidden params, unseen by you)

The grader runs `/app/nsga.py` on 3 hidden params files (different seeds,
different sizes, and a 3-objective `triplane` case) and, for every case:

- **(a) feasibility + recompute**: every returned solution must be feasible
  and its reported objectives must match the grader's independent recompute
  from the encoding (exact for knapsack; `rtol=1e-6`/`atol=1e-9` for
  continuous).
- **(b) non-domination**: no returned front point may dominate another
  (minimization; tolerance `1e-7`).
- **(c) hypervolume**: the reported `hypervolume` must match an independent
  exact computation from your own returned front, with the documented
  reference (`rtol=1e-6`).
- **(d) quality gates**:
  - `knapsack`: `HV(your front) ≥ 0.85 × HV(front of an independent
    reference NSGA-II run, same seed and budget)`. Hardcoded fronts and
    single-objective optimizers fail this by a wide margin.
  - `saddle`: your front's **IGD** (below) must be strictly below `0.9×` the
    median of 5 random-search fronts that use the same evaluation budget
    (`pop × generations` uniform samples). A correct NSGA-II is typically
    2–8× better than this baseline; naive/single-objective search is not.
  - `triplane`: the documented **front property** must hold: over your
    front, `mean(|f1²+f2²+f3 − 1|) ≤ 0.05` and `max(|f1²+f2²+f3 − 1|) ≤
    0.25`, and the front must span at least `0.6` in both the `f1` and `f2`
    directions.
- Plus a **source inspection**: the implementation must actually contain the
  core NSGA-II components (non-dominated sorting, crowding distance,
  tournament selection, crossover, mutation, hypervolume computation) with
  their recognizable names — a stub that never implements them fails.
- Front size must be ≥ 5 in every case (any real run on these problems has
  far more).

**IGD definition** (for `saddle`): with reference set `R = { (i/60, 1−(i/60)²)
: i = 0..60 }` (61 points on the analytic front) and your front `P` (raw
objective tuples),
`IGD(P, R) = (1/61) · Σ_{r∈R} min_{p∈P} ‖p − r‖₂` (Euclidean in objective
space).

## Suggested workflow

```bash
cd /app
python3 nsga.py params.json out.json        # visible knapsack case
# then write your own saddle/triplane params files to check those too, e.g.:
# echo '{"problem":"saddle","pop":50,"generations":70,"seed":42424242}' > /tmp/s.json
# python3 nsga.py /tmp/s.json /tmp/sout.json
```

Smoke-check your output: every objective recomputes from its encoding, the
front is mutually non-dominated, the hypervolume is consistent, and — on
your saddle run — the front hugs `f2 = 1 − f1²` with good coverage.