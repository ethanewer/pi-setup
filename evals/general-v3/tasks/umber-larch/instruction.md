# Umber-larch: estimate an average treatment effect to high accuracy

You are evaluating an observational study. The study design (which variables
cause which) is fully specified by a DAG; the outcome-generating process is
**not** linear-additive, so a careless model will not reach the required
accuracy. Produce a point estimate of the **average treatment effect (ATE)** —
the total effect of the treatment on the outcome — accurate to within
**±0.06** of truth.

`python3` with `numpy` is available; no network.

## Shipped files (do not modify)

- `/app/obs.csv` — observational data, one header row, one row per unit.
  Column names match the node names in the DAG.
- `/app/dag.json` — the study DAG:
  ```json
  {"nodes": ["school_rating", ...],
   "edges": [["parent", "child"], ...],
   "treatment_column": "treat",
   "outcome_column": "outcome"}
  ```

## The adjustment rule (normative)

Backdoor adjustment: a parent of the treatment belongs in the adjustment set
**iff it still has a directed path to the outcome in the graph obtained by
deleting the treatment node and all of its edges**. Adjust for exactly that
set. Variables caused by the treatment (directly or indirectly) must never
enter the adjustment set.

## Estimation requirement

Fit an outcome model for `E[outcome | treatment, adjustment set]` and compute
the ATE by **g-computation**: predict every unit's outcome under treatment
set to 1 and under treatment set to 0, and average the difference.

Be careful: the shipped studies' outcomes depend on covariates
**nonlinearly** (squared terms of continuous covariates) and through
**treatment × covariate interactions**. A model that adjusts for the wrong
variables misses the ±0.06 tolerance by a wide margin, and purely
additive-linear specifications are not guaranteed to reach it — make the
outcome model flexible enough (e.g., include squared terms of continuous
covariates and treatment × covariate interactions).
The grader's hidden studies differ in size, noise, effect strengths, column
names, and DAG topology — the same estimation procedure must work on all of
them, driven only by the passed-in files.

## Deliverables (both required)

1. **`/app/estimate.py`** — a reusable estimator:
   ```
   python3 /app/estimate.py <obs.csv> <dag.json> <out.txt>
   ```
   It reads the data and DAG from the given paths (never hard-code column
   names or values) and writes the estimated ATE to `<out.txt>` as a **single
   line containing exactly one number with 6 decimal places**
   (e.g. `1.980123`).

2. Run it on the shipped study:
   ```
   python3 /app/estimate.py /app/obs.csv /app/dag.json /app/answer.txt
   ```
   leaving **`/app/answer.txt`** in place.

The grader re-runs `/app/estimate.py` unchanged on hidden studies and checks
that every estimate is a single well-formatted number within ±0.06 of that
study's true total ATE.
