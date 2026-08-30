# Calibrate the wafer-yield rank model

The **Cobalt-Tide** fab run left you a matrix of process-sensor features and
the measured wafer yield for every lot in the run. Process engineers do not
care about absolute yield forecasts — they care about **ranking**: which wafers
came out better than which. Your job is to author a modelling program that
achieves a **strict rank-accuracy gate** (Spearman rank correlation >= 0.92)
between predictions and measured yield on **held-out** wafers, robustly across
repeated random seeds, and that generalises to fresh fab runs of the same form
(the verifier re-executes your program on datasets it has never shown you).

## Environment

- Working directory: `/app`. It already contains the input files
  `/app/wafer_features.npy` (an `(n, d)` float64 feature matrix, n = 2500,
  d = 10) and `/app/wafer_yield.npy` (the matching `(n,)` float64 measured
  yield vector, higher = better yield). Python 3.12 with numpy, scipy, pandas
  and scikit-learn is installed.
- **Do not modify `/app/wafer_features.npy` or `/app/wafer_yield.npy`.**

## Deliverables (both required)

1. `/app/train_yield.py` — a runnable Python program with this interface:
   ```
   python3 /app/train_yield.py --features <X.npy> --target <y.npy> \
       --n_seeds 10 --threshold 0.92 --out <report.json>
   ```
   It must read the feature matrix and target vector, train/tune a model, and
   write the rank-accuracy report described below to the given output path.
   It must work on any features/target pair conforming to the contract below.

2. `/app/yield_report.json` — the report your program produces **when run on
   the provided `/app/wafer_features.npy` and `/app/wafer_yield.npy`**:
   ```
   python3 /app/train_yield.py --features /app/wafer_features.npy \
       --target /app/wafer_yield.npy --n_seeds 10 --threshold 0.92 \
       --out /app/yield_report.json
   ```

## What the program must do

The relationship between the sensor features and yield is **not documented** —
the program must learn it from the data. For each requested seed
`s = 0 .. n_seeds-1`:

- split the row indices into a train set and a **held-out** test set using a
  random split with `random_state = s` and a test fraction you choose, kept
  within `[0.1, 0.3]` (e.g. 0.2) so the holdout is real;
- fit your model on the train rows only;
- predict on the held-out rows and record the **Spearman rank correlation**
  between your predictions and the measured yield on exactly those rows.

**The gate:** every seed's held-out Spearman must be `>= threshold`.
A naive linear regression on the raw features lands around Spearman ~0.55-0.60
on this data — far below the gate — because the true process response is
strongly nonlinear in the sensors. Beware: an *untuned* off-the-shelf
RandomForest also fails this gate (min over seeds ~0.85-0.89). You must
actually tune features/model (a properly configured nonlinear ensemble reaches
min-over-seeds ~0.94+ on all datasets of this form).

## Report JSON schema (exact keys)

```json
{
  "feature_columns": 10,
  "n_rows": 2500,
  "n_seeds": 10,
  "threshold": 0.92,
  "test_fraction": 0.2,
  "all_pass": true,
  "min_spearman": 0.948123,
  "seeds": [
    { "seed": 0, "n_train": 2000, "test_size": 500,
      "spearman": 0.960411,
      "test_ids": [3, 17, ...], "test_pred": [0.31, -2.05, ...] },
    ...
  ]
}
```

Hard requirements checked by the verifier (which **re-executes** your program):

- `feature_columns` = number of columns of the input matrix; `n_rows` = its
  number of rows; `n_seeds` = the requested count with each seed
  `0 .. n_seeds-1` present **exactly once**.
- `test_fraction` is the fraction you actually used and must lie in
  `[0.1, 0.3]`. For each seed, `n_train + test_size == n_rows` and
  `len(test_ids) == len(test_pred) == test_size`.
- `test_ids` are integer row indices into the input matrix; `test_pred` are
  the predicted values on exactly those rows. The verifier recomputes Spearman
  from your `test_pred` against the ground-truth target at `test_ids` and
  requires the recomputed value to be `>= threshold` **on every seed**; the
  reported `spearman` must agree with the recomputed value (within 0.01).
- The holdout must be a genuine random split per seed and the **test-id sets
  must differ between seeds** (reusing one split for every seed fails).
- `all_pass` must be `true` and `min_spearman >= threshold`.

## Error handling

- If the feature matrix and the target vector have **incompatible shapes**
  (different row counts), print an error to stderr and **exit non-zero**.
- If either file is missing, unreadable, or not a valid `.npy` array, print an
  error to stderr and **exit non-zero**.
- If the dataset has **fewer than 10 rows**, print an error to stderr and
  **exit non-zero** (no meaningful holdout exists).

## Constraints

- The verifier runs your program **unchanged** on hidden fab runs of the same
  form (same relationship family, different `n`, different `d`, different
  noise draw), so do not hard-code to the provided matrix's shape or content.
- No network access at verify time; standard library plus the installed
  numpy/scipy/pandas/scikit-learn.
- Fixed seeds: default behaviour must be deterministic for a given
  `--n_seeds`/`--threshold` (seed your split and any model randomness per-seed).
- Do not modify `/app/wafer_features.npy` or `/app/wafer_yield.npy`.
