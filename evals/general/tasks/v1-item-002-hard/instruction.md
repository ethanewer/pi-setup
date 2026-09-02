# Item-002 (hard) — Recover a DAG with a distractor variable, fit it, do
# causal interventions, and score the fitted model out-of-sample

You are a data scientist hardening a causal-inference pipeline. The dataset
contains a **distractor variable** that looks suspicious but is in fact fully
independent — a competent structure learner must exclude it. The pipeline also
requires proper out-of-sample model evaluation.

## Data

- `/workspace/data/graph2_train.csv` — 150,000 rows, header `X, Y, Z, W`,
  comma-separated. i.i.d. draws from a **linear Gaussian Bayesian network**.
- `/workspace/data/graph2_test.csv` — 120,000 held-out rows from the **same
  distribution** (same generative process, no overlap).

Only structural assumption you may use:

> Arrows only ever point from an earlier column to a later column in the
> ordering **X, Y, Z, W**.

So candidate parents are: `Z ⊆ {X, Y}`, `W ⊆ {X, Y, Z}`; `X` and `Y` are
potential roots. **One of the candidate parents is a complete distractor: it has
no true arrows at all — recover the structure from the data and prove that.**

## Deliverables (in `/app`)

### 1. `/app/edges2.json` — learned DAG
JSON object with, for each of `X, Y, Z, W`, its parent array, e.g.
`{"X": [], "Y": [], "Z": [...], "W": [...]}`. A candidate is a true parent only
if the node depends on it beyond the other candidate parents.

### 2. `/app/model2.json` — fitted model
Intercept + one coefficient per learned parent for each node (OLS), roots get
their sample mean as intercept and empty `coefs`. Same schema as below:

```json
{
  "X": {"intercept": 0.0, "coefs": {}},
  "Y": {"intercept": 0.0, "coefs": {}},
  "Z": {"intercept": 0.0, "coefs": {"X": 0.8}},
  "W": {"intercept": 0.0, "coefs": {"X": 1.1, "Z": 0.7}}
}
```

(Fits must come from the **train** data only.)

### 3. `/app/intervention2.json` — causal interventions
Using the learned DAG + train-fitted model, compute the **do-operator effect**
of each of `X`, `Y`, and `Z` on `W` with this exact protocol:

- `mean_C` = sample mean of the cause column (train data).
- `value(node, fixed)`: if `node` in `fixed` → that value; else if `node` has
  no parents → its train sample mean; else
  `intercept[node] + Σ coef[node][parent] * value(parent, fixed)`.
- `E_low = value(W, {})`, `E_high = value(W, {cause: mean_C + 1.0})`,
  `effect = E_high − E_low`.

Write:

```json
{
  "effects": [
    {"cause": "X", "target": "W", "effect": 1.66},
    {"cause": "Y", "target": "W", "effect": 0.0},
    {"cause": "Z", "target": "W", "effect": 0.7}
  ]
}
```

(Format placeholders — compute real values with your model; if your structure
correctly excludes the distractor, its effect is ~0.)

### 4. `/app/score2.json` — out-of-sample fit (DAG fitting)
Using **only** the train-learned parents and train-fitted coefficients, predict
every non-root variable on the **test** set. Combined RMSE:

```
score = sqrt( mean over all test rows of ( (predZ − Z)² + (predW − W)² ) / 2)
```

Write `{"rmse": <score>}`. The reference score is computed exactly this way by
the evaluator (≈0.15); a model that overfits the test set or misses a true
edge will not match it.

### 5. Validate
Run `cd /app && python3 evaluate.py`. It re-derives the ground truth from the
CSVs, checks all four deliverables, prints a per-section `PASS`/`FAIL` report
and the overall verdict, and writes `/app/status.txt`. Work in stages and
iterate until it prints `PASS`.

## Success criteria

All four JSON files exist and pass the evaluator/verifier checks
(structure exact; intercepts/coefficients ±0.3; effects ±0.5; score ±0.03).
Do not modify either CSV or `evaluate.py`.