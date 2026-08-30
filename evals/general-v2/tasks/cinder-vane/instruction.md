# Peakline lift-telemetry calibrator — Hydra debug mode

Peakline Resorts fits a small logistic calibrator over ski-lift telemetry to
predict whether a lift needs recalibration. The trainer in `/app` must be
**Hydra-driven** and expose a **config-group mode override** so operators can
run a fast debug pass. You work in `/app`. Do **not** modify
`/app/data/readings.csv` and do **not** touch `/tests` or `/solution`.

## Deliverables (all required, all under `/app`)

1. `/app/train.py` — the Hydra-driven trainer (contract below).
2. `/app/config.yaml` — the root Hydra config (defaults list includes the
   `mode` config group).
3. `/app/mode/standard.yaml` — the standard mode group file.
4. `/app/mode/debug.yaml` — the debug mode group file.
5. `/app/report.json` — the report produced by a **default** run
   (`python3 /app/train.py`) on `/app/data/readings.csv`.
6. `/app/model.json` — the fitted model produced by that same default run.
7. `/app/report_debug.json` and `/app/model_debug.json` — the report and model
   produced by running `python3 /app/train.py mode=debug` (no other overrides).

Items 5 and 6 must be genuine outputs of running `/app/train.py` — do not
hand-author them.

## Config contract (exact keys and values)

`/app/config.yaml` must contain (at least):

```yaml
defaults:
  - _self_
  - mode: standard
dataset: /app/data/readings.csv
learning_rate: 0.05
l2: 0.001
seed: 7
outputs:
  model: /app/model.json
  report: /app/report.json
```

`/app/mode/standard.yaml`:

```yaml
# @package _global_
epochs: 40
batch_size: 64
debug: false
```

`/app/mode/debug.yaml`:

```yaml
# @package _global_
epochs: 1
batch_size: 8
debug: true
outputs:
  model: /app/model_debug.json
  report: /app/report_debug.json
```

The `# @package _global_` directive makes each mode file's keys merge into the
root config (so `cfg.epochs` / `cfg.batch_size` / `cfg.debug` resolve directly).
The trainer must compose this config with Hydra so that all of the following
invocations work (run from any working directory):

```
python3 /app/train.py
python3 /app/train.py mode=debug
python3 /app/train.py mode=debug dataset=/SOME/NEW/readings.csv \
    outputs.model=/SOME/NEW/model.json outputs.report=/SOME/NEW/report.json
```

Hydra must be the config mechanism (i.e. `mode=debug` selects the
`mode/debug.yaml` group file; key overrides like `dataset=...` and
`outputs.report=...` must also work). Use Hydra's compose/initialize API or
`@hydra.main` — either is fine, as long as the overrides above behave exactly
as documented and the script does not change its behavior based on the current
working directory.

## Trainer behavior (every run, standard or debug)

1. Load the CSV at `cfg.dataset`. Header (exact order):
   `vibration,hours_since_service,load,needs_recal`. The first three columns
   are numeric features, `needs_recal` (0/1) is the binary target. Let
   `n_rows` and `n_features=3` be recorded from the data.
2. Fit a logistic regression with plain mini-batch SGD in numpy:
   - weights start at zeros (bias included separately),
   - `numpy.random.default_rng(cfg.seed)` draws the epoch permutations,
   - for each of the effective epochs, iterate mini-batches of
     `cfg.batch_size` rows in the permuted order, apply the gradient step with
     learning rate `cfg.learning_rate` and L2 penalty `cfg.l2` on the weights
     (not the bias),
   - the **effective epoch count** is `cfg.epochs` (40 standard, 1 in debug)
     and the batch knob is `cfg.batch_size` (64 standard, 8 in debug).
3. Compute training `accuracy` (fraction of rows whose predicted 0/1 equals
   the label) and the mean logistic loss `final_loss` after the last epoch.
4. Write the model to `cfg.outputs.model` as JSON:
   `{"weights": [<3 floats>], "bias": <float>, "n_features": 3}`.
5. Write the report to `cfg.outputs.report` as JSON with exactly these keys:

```json
{
  "debug": false,
  "epochs_effective": 40,
  "batch_size": 64,
  "learning_rate": 0.05,
  "l2": 0.001,
  "seed": 7,
  "dataset": "/app/data/readings.csv",
  "n_rows": 420,
  "n_features": 3,
  "accuracy": 0.0,
  "final_loss": 0.0
}
```

(`debug`, `epochs_effective`, `batch_size` come from the composed mode group;
`n_rows` from the actual data; `accuracy`/`final_loss` are floats.)

6. Print one short line to stdout containing `TRAIN_OK` and exit 0.

A standard run on well-conditioned data must reach training accuracy of at
least **0.75**. Debug runs (a single epoch) may land anywhere — no accuracy
gate applies to them.

## Debug-mode semantics (`mode=debug`)

`python3 /app/train.py mode=debug` must keep every other default exactly as
in the standard composition — same `dataset`, `learning_rate`, `l2`, and
`seed` — while `debug` becomes `true`, the effective epoch count becomes `1`,
and the batch size becomes `8`. The debug group file also redirects the debug
run's artifacts to `/app/model_debug.json` and `/app/report_debug.json`, so a
debug run must **not** modify `/app/report.json`, `/app/model.json`, or any
other standard-mode output. (Explicit key overrides such as
`outputs.report=...` still win over the group file, as usual in Hydra.)

## Grader behavior

The grader re-runs `/app/train.py` (unchanged) on the visible dataset and on
fresh hidden telemetry datasets with the documented overrides, and checks the
reports, the mode-group files, and that each written model file is a valid
3-feature logistic model whose predictions reproduce the reported accuracy on
its dataset. Do not hard-code row counts, dataset paths, or accuracies.

No network access is needed; `numpy` and `hydra-core` are installed.
