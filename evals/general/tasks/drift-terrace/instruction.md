# Drift-terrace: harden a logistic pipeline into a config-driven, deterministic, persistable job

## Goal

A small analytics repo trains a binary logistic classifier on a company CSV but
currently saves nothing reproducible and leaves the sign of one target feature's
coefficient unconstrained. Harden the pipeline so that:

1. **The designated feature's coefficient is strictly negative.**
2. The data is split into **fixed (seeded) folds** and an **accuracy floor is met
   on the held-out rows**.
3. The fitted model — **parameter vector and its shape** — plus a **plain numeric
   vector file** are persisted.
4. **Every data/output path and every tuning knob comes from config**, including a
   **debug override that shortens training to one epoch**, so the same script runs
   unchanged on a fresh dataset mounted at verify time.
5. Config/progress are written under the **expected experiment-data directory**.

You write the program, the config, and the artifacts in `/app`. A grading harness
reruns `/app/train.py` — unmodified — on the visible dataset and on hidden datasets.

## Environment

- Python 3.12 with `scikit-learn`, `scipy`, `pandas`, `numpy`, `joblib`,
  `hydra-core` and `pyyaml` preinstalled.
- `/app/company.csv` — the training dataset (a CSV with a header row, all feature
  columns numeric, plus a binary target column `churn` with values 0/1).
- Every other deliverable is **yours to create**.

## Deliverables (all must exist in /app)

| Path | Required content |
|------|------------------|
| `/app/train.py` | Executable Python trainer described below. |
| `/app/config.yaml` | The config your trainer consumes for the visible run. |
| `/app/model.joblib` | joblib dictionary of the fitted model. |
| `/app/vector.out` | Plain-text numeric vector file (see format). |
| `/app/experiment-data/progress.log` | Run/progress metadata (see format). |
| `/app/experiment-data/config.yaml` | A copy of the config used for the run. |

## The program: `/app/train.py`

Runnable as:

```
python3 /app/train.py --config CONFIG [--out DIR] [--logs DIR] [--data PATH]
```

- `--config` (default `/app/config.yaml`): YAML file holding every knob and path.
  It must contain (at least) these keys — use these exact names:

  ```yaml
  data:
    path: <csv path>
    target_column: <str>        # binary 0/1 column name
    drop_columns: [<str>...]    # extra columns to ignore before feature building
    id_column: null|"<str>"     # optional id column to drop
  model:
    reg_strength: <float>       # L2 penalty
    max_iter: <int>             # full training budget
  optim:
    driver_feature: <str>       # designated feature -> must be strictly negative
    bound_epsilon: <float>      # strictness margin, e.g. 0.0001
  split:
    seed: <int>                 # fixed fold seed
    n_folds: <int>
    held_out_fold: <int>        # 0-based fold index used as the held-out test fold
  evaluate:
    accuracy_floor: <float>     # minimum held-out accuracy
  debug:
    one_epoch: <bool>           # true -> limit training to one epoch
  output:
    dir: <dir>
    model_file: <str>
    vector_file: <str>
    log_dir: <dir>
    progress_file: <str>
  ```

- `--out` overrides `output.dir` (where `model_file` and `vector_file` land).
- `--logs` overrides `output.log_dir` (where `progress_file` and the config copy land).
- `--data` overrides `data.path`. **`train.py` must never hardcode `/app/company.csv`.**

Training must:

- Load the CSV, drop `drop_columns` and the optional `id_column`, keep all remaining
  columns except the target as features, and force the `driver_feature`'s coefficient
  to be **strictly negative** (well below zero, e.g. `< -bound_epsilon`). A box-
  constrained optimizer (e.g. `scipy.optimize.minimize` with `L-BFGS-B` bounds and
  your own logistic cross-entropy gradient) is a sound approach.
- Build a **fixed fold split**: `StratifiedKFold(n_splits=n_folds, shuffle=True,
  random_state=seed)`; train on all folds except `held_out_fold` and report/validate on
  `held_out_fold`.
- Compute held-out accuracy and require it to be `>= accuracy_floor`.

Persistence:

- Write `model.joblib` (via `joblib.dump`) as a dict that at minimum contains
  `feature_names` (list, in the same order the coefficients are stored), `coef`
  (1-D numeric vector, one value per feature), `intercept` (scalar), `coef_shape`
  (list describing the coefficient shape), and `constrained_feature` (the designated
  feature name).
- Write `vector.out` as **plain text**:
  - line 1: the integer number of coefficients `d`;
  - the next `d` lines: each coefficient, one per line (at least 6 decimal places);
  - a final line: the intercept.
- Write `progress.log` under the log dir with at least:
  ```
  epochs=<N>
  ```
  where `N` is the solver iteration budget actually used.

### Debug one-epoch override

When `debug.one_epoch` is `true`, `train.py` must **limit the optimizer to a single
epoch/iteration** and record `epochs=1` in `progress.log`. This is a debugging
shortcut, not a full-quality run.

### Self-test output

After training, `train.py` must print a self-test report to stdout in a
pass/fail form that includes per-check lines starting with `SELFTEST`, each ending
in `PASS` or `FAIL` (at least: the driver-coefficient sign check and the held-out
accuracy check), plus a mean statistic line of the form `SELFTEST MEAN_ACC=<float>`.
Exit non-zero if any hard check fails.

## Formats the harness checks (be exact)

- `model.joblib` → `feature_names`, `coef` (1-D, length == number of features),
  `intercept`, `coef_shape`, `constrained_feature`.
- The coefficient of `constrained_feature` must be `< -bound_epsilon` (strict).
- `vector.out` must parse as: count, then that many coefficient floats, then the
  intercept; the coefficient floats must match `model.joblib`'s `coef` to ~1e-3 and
  the last float must match the model intercept.
- Held-out accuracy (recomputed by the harness with the same seeded fold split from
  the config) must be `>= accuracy_floor` when the config does not use the one-epoch
  debug override.
- `progress.log` under the log dir must exist and, for the one-epoch debug case,
  contain `epochs=1`.

## Hidden sets

At verify time the harness mounts several fresh datases under `/tests/hidden` and
reruns your **unchanged** `/app/train.py` against each of their configs. These hidden
cases are genuinely different scenarios:

- different feature column names and targets;
- **extra junk columns** that must be ignored via `drop_columns` (the harness builds
  the feature matrix from your stored `feature_names`, not from raw column order);
- different fold counts/held-out indices/seeds and different accuracy floors;
- one case that **forces `debug.one_epoch: true`** to confirm the override shortens
  training (that case is not scored on accuracy).

Because the harness derives the feature set from the model's own `feature_names`,
select features from the config (drop the junk columns), not from hardcoded indexes.
Your program must work for any CSV whose columns match what its config describes.

## What you must NOT do

- Do not hardcode `/app/company.csv`, dataset column names, or dataset row counts
  inside `train.py`; everything comes from config.
- Do not modify or reorder the fixture CSV in place; treat it as read-only input.
- Do not rely on files under `/tests` during development (they only appear at verify
  time). Build and smoke-test against `/app/company.csv`.
