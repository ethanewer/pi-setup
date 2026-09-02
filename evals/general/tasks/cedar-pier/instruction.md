# Willow Harbor crane-shift trainer — hardening contract

You are handed a small analytics repo in `/app` that trains a logistic
classifier over crane-shift logs. Right now it is fragile and un‑reproducible.
Your job is to **harden the pipeline** so it behaves as the verifier expects and
generalizes to a brand-new dataset that will be mounted at verify time.

You work in `/app`. Do **not** touch `/tests` or `/solution` (they are mounted
read-only / absent — you never see them). Leave `data/company.csv` and
`data/val_company.csv` untouched.

## The data

`/app/data/company.csv` has these columns (stable header order):

```
hours, projects, years_review, tier, service_score, broke_down
```

- `broke_down` is the **binary target** (0/1).
- The five other columns are numeric **features** used to predict it.
- `years_review` is the **constraint feature**: its fitted coefficient in the
  persisted model **must be strictly negative** (sign < 0). More years since a
  safety review must *lower* breakdown risk.
- `/app/data/val_company.csv` has the same schema and is a held‑out evaluation
  set you can measure accuracy on.

## The four deliverables you must produce in `/app`

1. `/app/train.py` — a config‑driven trainer (see the interface contract below).
2. `/app/config.yaml` — the Hydra config that drives everything.
3. `/app/model.joblib` — the fitted scikit‑learn linear classifier, written by
   running `/app/train.py`.
4. `/app/vector.out` — a **plain numeric vector file**, one number per line,
   holding the fitted parameter (coefficient) vector, written by the same run.

Every product must be genuinely produced by running your trainer — do not
hand‑author the model dump or the vector.

## The trainer contract (this is the API the verifier calls)

`/app/train.py` must be a **Hydra‑driven script** whose default config is
`/app/config.yaml`. It must respect all of these keys (spelling matters):

```yaml
paths:
  dataset: /app/data/company.csv
  validation: /app/data/val_company.csv
  serialized: /app/model.joblib
  vector: /app/vector.out
  experiment: "/app/experiment/run-42/seed-6"
data:
  target: "broke_down"
  constrained_feature: "years_review"
  split_folds: 5
  split_seed: 11
training:
  epochs: 260
  batch_size: 256
model:
  penalty: "l2"
  C: 0.9
metrics:
  accuracy_floor: 0.80
debug:
  enabled: false
  epochs: 1
  batch_size: 4
```

The verifier invokes it like this, from a shell whose working directory is
`/app`:

```
python3 /app/train.py                                   # default run
python3 /app/train.py debug.enabled=true                # debug (one epoch)
python3 /app/train.py paths.dataset=/SOME/NEW/train.csv \
   paths.validation=/SOME/NEW/holdout.csv \
   paths.serialized=/tmp/x/model.joblib \
   paths.vector=/tmp/x/vector.out \
   paths.experiment=/tmp/x/exp                          # fresh dataset
```

Required behavior of every run (normal **and** debug):

1. **Schema check first.** Read `paths.dataset`. If the CSV is missing the
   `data.target` column (`broke_down`) or the `data.constrained_feature`
   column (`years_review`), print a clear error to stderr and **exit
   non‑zero** without writing any model or vector file. Same for an entirely
   empty table or for non‑numeric (missing/NaN) feature cells.
2. **Fixed, reproducible folds.** Split the training rows into
   `data.split_folds` folds using `StratifiedKFold(shuffle=True,
   random_state=data.split_seed)`. The same input must always get the same
   fold assignment. Record the fold sizes / assignment in the progress file
   (below).
3. **Fit.** Fit a scikit‑learn **linear** classifier (`LogisticRegression`,
   using `model.penalty`, `model.C`, and a max‑iterations bound derived from
   the effective epoch count — `training.epochs` normally, `debug.epochs`
   when debug is active) on the raw numeric features to predict the target.
   Do **not** scale/transform features in a way that changes their meaning —
   the raw feature columns are fed to the model so `model.predict` works
   directly on a held‑out CSV of the same schema.
4. **Sign constraint.** Guarantee the coefficient for
   `data.constrained_feature` (`years_review`) is **strictly negative** in the
   persisted model (`model.coef_[0, idx] < 0`, where `idx` is the column index
   of `years_review` among the feature columns). If you need to enforce it
   (e.g. refit on a mirror‑flipped feature column and remap the coefficient to
   its negative), keep the whole thing a valid single scikit‑learn linear
   model whose coefficient vector still has **one entry per feature**, in the
   same feature order, and which still predicts correctly on the *natural*
   (unflipped) feature space.
5. **Accuracy gate.** Evaluate the fitted model on `paths.validation`, which
   has the same schema. Compute overall accuracy (`(predicted == true).mean()`).
   A **normal** (non‑debug) run must achieve
   `accuracy >= metrics.accuracy_floor` (0.80). If it does **not**, print the
   measured accuracy to stderr and exit non‑zero. Debug runs are allowed to
   miss the floor (they only train one epoch).
6. **Persist.** In a normal run write:
   - the model to `paths.serialized` (joblib),
   - the fitted coefficient vector to `paths.vector` — a plain row‑wise
     numeric file, one coefficient per line, loadable with `numpy.loadtxt`
     back into a vector of length `(#features, 1)`.
   Debug runs write their own model/vector/artifacts under the debug directory
   (7) and must **not** overwrite the normal `paths.serialized` /
   `paths.vector`.
7. **Experiment‑data directory.** After every run write *real* content into
   the directory rooted at `paths.experiment`:
   - `config_snapshot.yaml` — a YAML snapshot of the effective (composed)
     config actually used, and
   - `progress.json` — a JSON progress record containing at least the fields
     `n_features`, `n_epochs_effective`, `batch_size`, `accuracy` (or `null`
     if not computed), `split_folds`, `split_seed`, `constrained_coef`,
     `fold_assignment` (the per‑row fold index list), and `debug_enabled`.
   Normal runs write these at `paths.experiment/`; **debug runs write them
   under `paths.experiment/debug/`** (i.e. `…/run‑42/seed‑6/debug/`). All dirs
   must be created as needed.
8. Print a short completion line to stdout and exit 0 (non‑debug successful).

## Debug mode (the `debug.enabled` override)

`python3 /app/train.py debug.enabled=true` must:
- keep every other default as‑is,
- set the **effective epoch count to `debug.epochs` (1)** and the batch‑size
  knob to `debug.batch_size` (4),
- still do the schema checks, validation, experiment‑dir writes — all under
  `paths.experiment/debug/` with `progress.json` reporting
  `n_epochs_effective == 1` and the small batch size,
- not touch the normal `/app/model.joblib` or `/app/vector.out`.

## What you must NOT do

- Do not read `/tests`, `/solution`, or hard‑code answers to hidden datasets.
- Do not remove columns or change the header of `company.csv`/`val_company.csv`.
- Do not only paste a pre‑computed `model.joblib`/`vector.out` — they must be
  the output of actually running `/app/train.py`.

## Hints

- The five raw features are already well‑conditioned: a plain `LogisticRegression`
  on them reaches roughly 88‑95% accuracy on fresh held-out data, and the
  natural `years_review` coefficient is about −1.0. Your main risks are a wrong
  output path, a malformed/NaN table that you don't detect, or a coefficient
  that slips to a non‑negative value on an edge dataset. Enforce the sign
  explicitly instead of hoping.
- Make all paths resolve when the dataset is mounted elsewhere (use the
  documented overrides; absolute paths are safest).