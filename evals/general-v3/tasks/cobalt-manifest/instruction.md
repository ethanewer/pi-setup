# Cobalt resupply manifest — an exact integer program

An orbital station must be restocked. You are given a catalog of cargo cell
types and must choose **nonnegative integer quantities** `q_i` — one per cargo
type — satisfying **equality-sum constraints** exactly, a volume budget, and an
explicit tie-break rule. You must deliver a **reusable solver program** that
computes the unique optimum for *any* valid manifest, not just the provided
one. Note: quantities must be integers — a linear relaxation or a
cost-efficiency greedy can be strictly off the true optimum here.

## Input format

`/app/manifest.json` is a JSON object:

```json
{
  "containers": 9,
  "mass": 54,
  "volume_limit": 30,
  "cargo": [
    {"name": "cell_a", "mass": 4, "volume": 3, "cost": 4, "science": 5},
    {"name": "cell_b", "mass": 6, "volume": 4, "cost": 5, "science": 8}
  ]
}
```

Constraints on the input (always true for manifests you receive):

- `containers` (`K`), `mass` (`W`), `volume_limit` (`V`) are nonnegative integers.
- Each cargo entry has a unique `name` (any string) and nonnegative integer
  `mass`, `volume`, `cost`, `science`. A `mass` of `0` may occur.

## Decision variables and totals

Pick integers `q_i >= 0`, one per cargo entry (in input order). Totals:

```
count   = sum(q_i)
mass    = sum(q_i * mass_i)
volume  = sum(q_i * volume_i)
cost    = sum(q_i * cost_i)
science = sum(q_i * science_i)
```

### Hard constraints (ALL must hold)

1. `count == containers`  (**exact** equality-sum constraint)
2. `mass == mass`         (**exact** equality-sum constraint)
3. `volume <= volume_limit`

### Objective (over feasible integer allocations)

Minimize `cost`; among cost ties, **maximize** `science`; among those ties,
choose the allocation whose quantity vector `(q_0, q_1, ..., q_{n-1})` —
ordered as in the input `cargo` list — is **lexicographically smallest**.
This rule always selects a single unique optimum.

## Deliverables

1. **`/app/solve.py`** — the solver:

   ```
   python3 /app/solve.py <input_manifest.json> <output_result.json>
   ```

   It reads the manifest, computes the unique optimum (or detects
   infeasibility), and writes the result JSON.

2. **`/app/manifest_result.json`** — the result produced by running your
   solver on the provided `/app/manifest.json`.

## Output format

Feasible instance — exactly this shape:

```json
{
  "cost": 41,
  "science": 57,
  "mass": 54,
  "volume": 29,
  "quantities": {"cell_a": 3, "cell_b": 2, "cell_c": 1, "cell_d": 3}
}
```

- `quantities` must contain **every** cargo name from the input (zeros
  included, names verbatim).
- `cost`, `science`, `mass`, `volume` must equal the values recomputed from
  `quantities` (exact integer arithmetic), and the totals must satisfy the
  hard constraints above.

Infeasible instance (no integer allocation satisfies all three hard
constraints):

```json
{"infeasible": true, "quantities": {}}
```

## Edge cases you MUST honor (all are probed by hidden instances)

- **Zero-mass cargo**: a `mass == 0` entry is bounded only by the exact count
  and volume constraints; handle it without unbounded loops.
- **Infeasibility**: e.g. parity (every cargo mass even but target `mass`
  odd), or targets unreachable within `volume_limit` — emit the infeasible
  form.
- **Empty cargo list**: with `containers == 0` and `mass == 0` this is
  feasible (all totals zero, `quantities` = `{}`); with `mass > 0` it is
  infeasible.
- **Volume-binding instances**: the cheapest count/mass-feasible allocation
  may exceed `volume_limit`; the optimizer must fall back to the next best.
- **Tie-breaking**: allocations that tie on `cost` and `science` must resolve
  to the lexicographically smallest quantity vector in input order.
- **Integer quantities only**: fractional (LP-relaxation) answers are invalid
  and will fail the exact-optimum comparison.

## Constraints / do not modify

- Write under `/app`. The original `/app/manifest.json` must remain unchanged
  (its checksum is verified), but your solver must read **arbitrary** manifests
  passed on the command line.
- Python standard library only; deterministic; no network. All arithmetic is
  exact integer arithmetic — never use floats in the objective.
