# Register the gearbox-fault triage model

You are given a small telemetry triage setup in `/app`. Two wind-farm sites
exported gearbox session logs as CSV files, and you must fit a scikit-learn
linear classifier that predicts the binary `fault` label, serialize it, and
register it with a machine-readable manifest. Everything is checked by a
verifier that **re-runs your program** on fresh datasets, so the program must
be generic, not tuned to the shipped files.

## Environment

- Working directory: `/app`. It contains `/app/data/site_a.csv` (training
  data) and `/app/data/site_b.csv` (held-out evaluation data). Python 3.12
  with `numpy`, `pandas`, `scikit-learn`, and `joblib` is available.
- Do **not** modify anything under `/app/data/`.

## Data format

Both CSVs share a stable schema: a header row, then one row per session. The
**last column is always the binary target `fault`** (values `0`/`1`); every
other column is a numeric feature. The shipped data has 5 features, but other
sites export **different feature sets** (between 3 and 6 features) with
different column names — your program must read the feature list from the CSV
header at runtime and must never hard-code the feature count or names.

## Deliverables (all three required)

1. `/app/fit_model.py` — a runnable Python program with this exact CLI:
   ```
   python3 /app/fit_model.py <train_csv> <holdout_csv> <model_out> <manifest_out>
   ```
   Behavior for **any** input conforming to the contract above:
   - Load `<train_csv>`. If the `fault` column is missing, the table is empty,
     or any feature cell is non-numeric/missing, print a clear error to
     stderr and **exit non-zero** without writing either output file.
   - Fit a scikit-learn **linear classifier** (`LogisticRegression` is fine)
     on the raw feature columns (do not scale or drop columns — the model must
     `predict` directly on a CSV with the same schema) with a fixed random
     seed, so identical inputs always produce an identical serialized model.
   - Compute accuracy on `<holdout_csv>` (same schema) as
     `(predicted == true).mean()`. If it is below **0.80**, print the measured
     accuracy to stderr and exit non-zero without writing the outputs.
   - Serialize the fitted model to `<model_out>` with `joblib.dump` (create
     parent directories as needed).
   - Write a JSON manifest to `<manifest_out>` with at least these keys:
     - `"n_features"`: number of feature columns (integer),
     - `"feature_columns"`: the feature column names in order (list of str),
     - `"target"`: `"fault"`,
     - `"holdout_accuracy"`: the measured holdout accuracy (float).

2. `/app/artifacts/model.joblib` — the serialized model produced by running
   your program on the shipped data:
   ```
   python3 /app/fit_model.py /app/data/site_a.csv /app/data/site_b.csv \
       /app/artifacts/model.joblib /app/artifacts/manifest.json
   ```

3. `/app/artifacts/manifest.json` — the manifest from that same run.

## What the verifier checks

- It executes `/app/fit_model.py` unchanged on the shipped data and on
  **hidden** site datasets (including feature counts other than 5).
- The persisted loaded object must be a genuine scikit-learn linear model:
  loading `<model_out>` with `joblib.load` yields an object with `coef_` and
  `predict` that is an instance of a scikit-learn linear model class.
- The coefficient vector length must equal the **input feature count** of the
  dataset it was trained on, and must match the manifest's `n_features`.
- The verifier recomputes holdout accuracy itself and requires
  `>= 0.80`, consistent with the manifest value.
- A hidden dataset that lacks the `fault` column must make your program exit
  non-zero without creating the model file.
- `/app/artifacts/model.joblib` and `/app/artifacts/manifest.json` must be
  real artifacts of a run on the shipped data (the verifier re-checks the
  same properties on them).

## Constraints

- No network access; standard libraries plus numpy/pandas/scikit-learn/joblib.
- Do not read or modify `/tests` or `/solution`.
- Do not hard-code file contents, feature names, or the feature count.
