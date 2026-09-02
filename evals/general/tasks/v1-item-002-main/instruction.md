# Item-002 (medium) — Learn a causal DAG from data and estimate a causal effect

You are a data scientist on a causal-inference team. Your colleague left you an
**observational dataset** and three deliverables to produce.

## Data

`/workspace/data/graph1.csv` — 100,000 rows, comma-separated, with a header
row and four numeric columns: `X, Y, Z, W`. The rows are i.i.d. draws from a
**linear Gaussian Bayesian network** (a structural-equation model). You do not
know the equations, but you may rely on exactly one structural assumption:

> Arrows in the causal graph only ever point from an earlier column to a later
> column in the ordering **X, Y, Z, W**. So the only candidate parents are:

```
parents(Z) subset of {X, Y}
parents(W) subset of {X, Y, Z}
X has no parents; Y has no parents.
```

All quantities below are computed from this dataset (no other data exists).

## Deliverables (in `/app`)

### 1. Structure learning — `/app/edges.json`

Recover, from the data itself, which earlier columns are **true parents** of
each node. Write exactly one JSON object listing, for each of the four
variables, its array of parent names:

```json
{
  "X": [],
  "Y": [],
  "Z": ["X", "Y"],
  "W": ["Y", "Z"]
}
```

(That example shows the *format* — determine the real parent sets from the
data. A parent belongs in the list only if the node genuinely depends on it
over and above the other candidate parents.)

### 2. Fitting — `/app/model.json`

Fit a linear Gaussian conditional model: for each node, an intercept plus one
coefficient per *discovered parent* (ordinary least squares of the node on its
parents; roots get their sample mean as the intercept and no coefficients).
Write exactly one JSON object:

```json
{
  "X": {"intercept": 0.0,   "coefs": {}},
  "Y": {"intercept": 0.0,   "coefs": {}},
  "Z": {"intercept": 0.0,   "coefs": {"X": 2.0, "Y": 1.5}},
  "W": {"intercept": 1.0,   "coefs": {"Y": 0.5, "Z": 2.5}}
}
```

### 3. Causal intervention — `/app/intervention.json`

Using the estimated DAG (structure) + fitted model, compute the **do-operator
causal effect** of each of `X` and `Y` on `W` with this exact protocol:

- Let `mean_C` be the sample mean of the cause column.
- Define `value(node, fixed)` recursively (topological order):
  - if `node` is in `fixed`, use that fixed value;
  - else if `node` has no parents, use its sample mean;
  - else `intercept[node] + sum(coef[node][parent] * value(parent, fixed))`.
- `E_low  = value(W, {})`
- `E_high = value(W, {cause: mean_C + 1.0})`
- `effect = E_high − E_low`

Write `/app/intervention.json`:

```json
{
  "effects": [
    {"cause": "X", "target": "W", "effect": 5.0,  "E_low": 3.0,  "E_high": 8.0},
    {"cause": "Y", "target": "W", "effect": 4.25, "E_low": 3.0,  "E_high": 7.25}
  ]
}
```

(The numbers shown are *format placeholders*, not answers — compute the real
values with your fitted model.)

### 4. Validate against the supplied evaluator

Run:

```bash
cd /app && python3 evaluate.py
```

It re-derives the ground truth from the dataset, checks your three files, and
prints a per-section `PASS`/`FAIL` report ending with the overall verdict; it
also writes `/app/status.txt`. Work in stages: get the structure right first,
then the fit, then the interventions, and keep iterating until everything
passes.

## Success criteria

`/app/edges.json`, `/app/model.json`, `/app/intervention.json` all exist, are
valid JSON, and pass every check in the evaluator (the verifier reapplies the
same checks with the same tolerances: structure exact; intercepts and
coefficients within ±0.3; effects within ±0.5). Do not modify
`/workspace/data/graph1.csv` or `evaluate.py`.