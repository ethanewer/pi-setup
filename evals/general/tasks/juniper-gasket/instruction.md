# Greenhouse Screening — fit a contamination screener to a stated accuracy

The greenhouse receives batches of potted plants and must screen out
contaminated batches before they enter the growing halls. You are given a
labeled training set of batch sensor readings and a separate **held-out
test set**. Fit a classifier on the training data that classifies the
held-out batches with **at least the stated accuracy floor**.

Everything runs on CPU in `/app` with `python3`, `numpy`, `pandas` and
`scikit-learn` (installed). Work only in `/app`; do not read `/tests` or
`/solution`.

## The data

The visible case lives in `/app/case/`:

- `train.csv` / `test.csv` — numeric sensor readings per batch with a
  binary target column `contaminated` (0 = clean, 1 = contaminated).
  The six feature columns are `moisture`, `weight_kg`, `metal_signal`,
  `odor_score`, `optical_density`, `conductivity`.
- `meta.json` — `case_id`, `seed`, `features` (the feature column list),
  `target` (`contaminated`), `accuracy_floor` (the stated minimum holdout
  accuracy, `0.85`).

The test set is strictly held out: it must never be used for fitting,
feature selection, or threshold tuning — only for the final reported
accuracy.

## Deliverables (both produced in `/app`)

Write ONE program, `/app/fit_screen.py`:

```
python3 /app/fit_screen.py <casedir> <outdir>     # defaults: /app/case /app
```

It must:

1. Read `meta.json` from `<casedir>` and take the feature list, target
   column and accuracy floor from it (do not hardcode column names,
   floors, or dataset sizes).
2. Fit a scikit-learn classifier on `train.csv` (any sensible model is
   fine; a scaled logistic regression clears the floor comfortably).
3. Evaluate once on `test.csv` and write into `<outdir>`:
   - `screen_model.pkl` — the fitted model, pickled, with a working
     `.predict(X)` that maps a feature matrix to class labels;
   - `screen_metrics.json` — JSON with keys `case_id`, `test_accuracy`,
     `accuracy_floor`, `meets_floor` (boolean:
     `test_accuracy >= accuracy_floor`).

Then run your program on the visible case so the artifacts appear in
`/app` itself:

```
python3 /app/fit_screen.py /app/case /app
```

The deliverables then exist at exactly `/app/fit_screen.py`,
`/app/screen_model.pkl`, `/app/screen_metrics.json`.

## Grading

The grader loads `/app/screen_model.pkl`, predicts on the visible held-out
test set, and requires accuracy `>= 0.85`; it also re-runs
`/app/fit_screen.py` unchanged on hidden cases (different seeds, sizes and
feature scales, same schema and format) and repeats the check with each
case's own `accuracy_floor`. Your program must therefore be fully
data-driven: no hardcoded columns, paths beyond the documented defaults,
or dataset-specific constants.

## Constraints

- Deterministic: seed your model so a re-run reproduces the same artifacts.
- Standard library + `numpy` + `pandas` + `scikit-learn` only; no network
  at verify time.
- Do not modify anything in `/app/case/`.
- The verifier treats a missing/unloadable model or metrics file as
  failure; guard your program's own error handling (e.g. a missing column
  should exit non-zero with a clear message rather than crash).
