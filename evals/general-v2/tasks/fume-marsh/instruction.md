# Fit and serialize a pump-fault linear classifier

You are given a pump telemetry dataset at `/app/data/pump_readings.csv`. Your
job is to build a small, reusable fitting tool, use it to produce a serialized
scikit-learn linear model and a manifest, and make sure the persisted artifacts
**reload correctly with the right parameter shape** on any conforming dataset.

Work in `/app`. Do **not** touch `/tests` or `/solution` (not visible to you).

## The data

`/app/data/pump_readings.csv` is a plain CSV with a header row. The **last**
column is the binary target (`fault`, values 0/1); **every other column** is a
numeric feature (the count of features may differ between datasets).

## Deliverables (all three required)

1. `/app/fit_model.py` — a runnable Python tool with this interface:
   ```
   python3 /app/fit_model.py <csv_path> <model_out> <manifest_out>
   ```
   Behavior:
   - Read the CSV. Validate first: if the file is missing, has fewer than 2
     columns, contains a non-numeric or empty (NaN) cell, print a clear error
     to **stderr** and **exit non-zero** without writing either output file.
   - Fit a **scikit-learn linear classifier** (e.g. `LogisticRegression`) on
     the raw numeric feature columns to predict the last column. Use enough
     iterations to converge (e.g. `max_iter >= 500`). Do not scale or drop
     columns; `model.predict` must work directly on the raw feature matrix.
   - Serialize the fitted model with **joblib** to `<model_out>`.
   - Write a JSON manifest to `<manifest_out>` with exactly these keys:
     ```json
     {
       "n_features": <int>,
       "n_samples": <int>,
       "feature_columns": ["<col>", ...],
       "target_column": "<col>",
       "model_class": "<sklearn class name, e.g. LogisticRegression>"
     }
     ```
2. `/app/model.pkl` — the joblib-serialized fitted model produced by running
   your tool on the provided `/app/data/pump_readings.csv`.
3. `/app/manifest.json` — the manifest produced by the same run:
   ```
   python3 /app/fit_model.py /app/data/pump_readings.csv /app/model.pkl /app/manifest.json
   ```

## What the grader checks

- Your tool is re-run unchanged on **hidden datasets** with different feature
  counts (including a single-feature dataset and a wide multi-feature one).
  For each run the persisted model is loaded with `joblib` and must be:
  - an instance of a **scikit-learn linear model** (its class lives under
    `sklearn.linear_model`),
  - with a coefficient vector whose length equals the dataset's **feature
    count** (number of CSV columns minus one),
  - whose `predict` works on the raw feature matrix and returns one
    prediction per row.
- The manifest must agree with the dataset (`n_features`, `n_samples`) and
  with the model (`model_class`).
- On a **malformed dataset** (empty/non-numeric cell) the tool must exit
  non-zero and write **neither** output file.
- The visible `/app/model.pkl` and `/app/manifest.json` must match the visible
  dataset.

## Constraints

- Standard library plus the preinstalled `scikit-learn` / `joblib` / `numpy`
  only. No network access.
- Do not hard-code to the visible CSV's feature count — the tool must handle
  any conforming CSV.
- Both `/app/model.pkl` and `/app/manifest.json` must be produced by actually
  running `/app/fit_model.py`, not hand-authored.
