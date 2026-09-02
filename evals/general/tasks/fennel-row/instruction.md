# Loamvale Orchard frost-risk trainer — experiment artifacts contract

You are hardening a tiny frost-risk trainer at **Loamvale Orchard** so every
run leaves **real, inspectable artifacts in its expected experiment
directory**. You work in `/app`. The fixtures `/app/data/orchard.csv` and
`/app/config.json` are already on disk. **Do not modify** `/app/data/orchard.csv`
or `/app/config.json`, and never read or touch anything under `/tests` or
`/solution`. The trainer is re-run on **hidden** datasets and hidden configs at
verify time, so it must be generic.

## Data

`/app/data/orchard.csv` has the stable header

```
chill_hours,rainfall_mm,soil_ph,frost
```

- `frost` is the binary target (0/1).
- `chill_hours`, `rainfall_mm`, `soil_ph` are numeric features.

## Deliverables

1. **`/app/config.json`** — the shipped config (already provided; leave it as
   is). It drives the visible run and has exactly this shape:

   ```json
   {
     "paths": {
       "dataset": "/app/data/orchard.csv",
       "experiment": "/app/experiments/frost-29/seed-5",
       "model": "/app/model.json"
     },
     "data": {"target": "frost", "features": ["chill_hours", "rainfall_mm", "soil_ph"]},
     "training": {"epochs": 120, "learning_rate": 0.05, "seed": 5}
   }
   ```

2. **`/app/train.py`** — a generic, deterministic trainer:

   ```
   python3 /app/train.py [--config <path>]
   ```

   - With no `--config`, it uses `/app/config.json`.
   - It trains a binary logistic regressor by gradient descent on the CSV at
     `paths.dataset` using the `data.features` columns and `data.target`.
   - It must be fully deterministic for a given config (fixed seed usage; do
     not depend on wall-clock, hashing order, or filesystem order).

3. **Experiment artifacts** — every run of `/app/train.py` must create the
   directory given by `paths.experiment` (e.g.
   `/app/experiments/frost-29/seed-5` for the visible config — note the
   `<base>/<run-name>/seed-<n>` layout) and write into it:

   - `config.json` — a copy of the **effective** config actually used by the
     run (same JSON keys/values as the input config).
   - `progress.json` — a JSON **list** of per-epoch training losses (plain
     finite floats), whose **length equals `training.epochs`** from the
     effective config.

   The run must also write the fitted model (weights and bias, plus the
   feature names and the epochs count) as JSON to `paths.model`
   (`/app/model.json` for the visible config).

4. **You must actually run the trainer on the visible config** so that these
   exist with real content:

   ```
   /app/experiments/frost-29/seed-5/config.json
   /app/experiments/frost-29/seed-5/progress.json
   /app/model.json
   ```

## Edge cases the grader probes

- **Hidden configs / datasets**: the verifier copies fresh CSVs into
  `/app/data/` and runs `python3 /app/train.py --config <hidden-config.json>`
  whose `paths.experiment` points at a **different** experiment directory and
  whose `training.epochs` differs. The exact directory named in that hidden
  config must then exist and contain the artifacts described above with
  matching content (epochs count, effective-config copy).
- **Missing parent directories**: the trainer must create the whole experiment
  path itself (parents included).
- **Real progress**: `progress.json` losses must be finite floats and the loss
  must actually decrease from first to last epoch on the provided data.
- **Do not hard-code** the visible paths, epoch count, or CSV contents —
  everything comes from the config.

## Constraints

- Standard library only; no network access; deterministic.
- Do not modify `/app/data/orchard.csv` or `/app/config.json`.
