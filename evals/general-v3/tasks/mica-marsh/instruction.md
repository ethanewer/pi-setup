# mica-marsh — interrogate & recover a black-box ReLU MLP

A frozen hardware scorer exposes a single scalar forward channel. Its core
is a one-hidden-layer ReLU network

```
f(x) = sum_i  v_i * relu(w_i . x + b_i)
```

with an unknown input matrix `W` (rows `w_i`), unknown output weights `v_i`
and biases `b_i`. You must recover the products `v_i * w_i` (one row per
hidden unit) **purely by querying the forward channel** — nothing else.

## Environment

- Working directory `/app`. Python 3.12 with `numpy` is installed.
- `/app/blackbox.py` defines the fixture class:

```python
from importlib import spec_from_file_location, module_from_spec
spec = spec_from_file_location("blackbox", "/app/blackbox.py")
mod = module_from_spec(spec); spec.loader.exec_module(mod)
model = mod.BlackBox()
```

- `model.in_dim` is the input length (the visible fixture has `in_dim = 4`
  and 6 hidden units).
- `model.query(x)` returns a `float` for any array-like `x` of length
  `model.in_dim`. **The only permitted channel is `model.query`.** The row
  products are not obtainable from any visible attribute, and you must not
  depend on fixture internals (no reading private attributes of the
  fixture module).

## Deliverables (both required)

1. `/app/probe_mlp.py` — a Python module exposing a fully general
   extraction routine (input dimension and unit count vary; do not
   hard-code the visible fixture):

   ```python
   def extract_rows(query, in_dim):
       """
       query  : callable returning float for an array of length in_dim
       returns: an (n_units, in_dim) array-like of floats recovering the
                rows v_i * w_i
       """
   ```

   Running `python3 /app/probe_mlp.py` must interrogate the fixture in
   `/app/blackbox.py` and write `/app/rows.json` (deliverable 2).

2. `/app/rows.json` — JSON of the form
   `{"rows": [[...], ...], "n_rows": <int>}` holding your recovered matrix
   for the visible `/app/blackbox.py`.

## Recovery contract

- The hidden units are arbitrary in number and `in_dim` varies; your
  routine must work on any compliant black box.
- Your matrix is accepted **up to a row permutation and an arbitrary
  nonzero per-row scaling** (including sign): every true row `v_i * w_i`
  must be matched by exactly one of your rows within a small tolerance,
  and you must return **exactly n_units rows** (no extras, none missing).
- Generators of fresh hidden fixtures guarantee every unit has a kink
  reachable along some axis (`|w_i[d]| >= 0.4` whenever `w_i[d] != 0`,
  `|v_i| >= 0.5`, `|b_i| <= 3`, kink locations pairwise separated), so a
  piecewise-linear analysis along the coordinate axes separates all rows.

## Query budget

The verifier wraps `query` with a counter and **fails a case if it exceeds**

```
4000 * in_dim + 1000 * n_units + 10000
```

queries. Wasteful brute-force grids over multi-dimensional regions will
not fit; be strategic (the piecewise-linear structure along
`x = t * e_d` is your friend).

## Constraints

- Write outputs only under `/app`; do not modify `/app/blackbox.py`.
- Deterministic behaviour preferred; the verifier calls `extract_rows`
  with fresh hidden fixtures (different `in_dim`, unit count, signs,
  near-zero biases).
- No network access; `numpy` is available.
