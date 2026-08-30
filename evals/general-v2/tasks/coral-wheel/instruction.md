# Find a feasible allocation with a Pareto-style score

You are given a catalog in `/app/portfolio.json`. Choose nonnegative integer
quantities `q_i` for the catalog entries, must satisfy three hard constraints,
and must attain a lexicographic objective. You must deliver a **reusable
program** that solves **any** valid catalog, not just the provided one.

## Input

`/app/portfolio.json` is a JSON object:

```json
{
  "budget": 100,
  "risk_limit": 31,
  "min_return": 47,
  "items": [
    {"name": "a", "cost": 13, "risk": 4, "return": 8},
    {"name": "b", "cost": 21, "risk": 7, "return": 12}
  ]
}
```

Constraints on the input:
- `budget`, `risk_limit`, `min_return` are nonnegative integers.
- Each item has a unique `name` and nonnegative integer `cost`, `risk`,
  `return`. Item names are unique within a catalog.
- No item ever has **both** `cost` and `risk` equal to `0` with a positive
  `return` (a reward-bearing free item would be unbounded; it never occurs).

Pick nonnegative integer quantities `q_i` (one per item). Define totals:

```
cost   = sum(q_i * cost_i)
risk   = sum(q_i * risk_i)
return = sum(q_i * return_i)
count  = sum(q_i)
```

### Hard constraints (an allocation must satisfy ALL three to be feasible)
1. `cost <= budget`
2. `risk <= risk_limit`
3. `return >= min_return`

### Objective (over feasible allocations)
Maximize `return`; among ties, minimize `risk`; among those ties, minimize
`count`. (`cost` matters only through the `budget` upper bound.)

## Deliverables

1. **`/app/solve.py`** — a generic, deterministic owner of the algorithm
   above. It must accept this exact interface:
   ```
   python3 /app/solve.py <input_portfolio.json> <output_result.json>
   ```
   It reads the input catalog, computes the unique optimum, and writes the
   output. The verifier runs it on fresh catalogs you have **not** seen, so
   handle every edge case listed below **exactly**.

2. **`/app/allocation.json`** — run `solve.py` on the provided
   `/app/portfolio.json` to produce the visible result. The verifier runs
   `solve.py` itself and independently re-checks this file.

## Output format

Feasible case (exactly this shape):

```json
{
  "cost": 99,
  "risk": 31,
  "return": 60,
  "item_count": 7,
  "quantities": {"a": 6, "b": 1, "c": 0, "d": 0}
}
```

- `quantities` must contain **every** item name from the input, zeros included.
- `cost`, `risk`, `return`, `item_count` must equal the values you recompute
  from `quantities` (exact integer arithmetic).

Infeasible case (no integer allocation meets all three constraints):

```json
{"infeasible": true, "quantities": {}}
```

## Edge cases you MUST honor (all are probed)

- **Zero `cost` or zero `risk` items.** When `cost == 0` the quantity is
  bounded only by `risk_limit`; when `risk == 0` only by `budget`. Bound the
  quantity correctly — do not loop forever.
- **Infeasible catalog.** If no combination reaches `min_return` within
  `budget` and `risk_limit`, emit the infeasible form.
- **Tie-breaking order:** maximize `return`, then minimize `risk`, then
  minimize `count`. Distinct allocations that tie on `return` **and** `risk`
  must resolve to the smaller `count`.
- **Empty catalog.** `items` may be `[]`; then all totals are `0`, `count` is
  `0`, and `quantities` is `{}`. Feasible exactly when `min_return <= 0`.
- **Names.** Preserve each item's `name` verbatim; do not reorder or rename.
- All arithmetic is integer-exact; never use floats in the objective.

## Constraints / do not modify

- Write under `/app`. `/app/portfolio.json` is provided for you to build the
  solver; its original contents must remain unchanged (the verifier depends on
  them and the solver must read arbitrary catalogs regardless).
- Python standard library is available; you may keep any helper files under
  `/app`. The verifier needs only `/app/solve.py` and `/app/allocation.json`.