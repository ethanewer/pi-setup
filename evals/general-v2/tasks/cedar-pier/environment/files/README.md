# Willow Harbor — crane shift analytics

This small repo trains a logistic classifier on shift logs to decide which
crane operators **broke_down** on a shift, so the crew can pre-schedule
maintenance. The columns are (header order is stable):

`hours, projects, years_review, tier, service_score, broke_down`

`broke_down` is the binary target; `years_review` is a **constraint feature**
that must always have a strictly negative fitted coefficient (more years since
a safety review must *lower* the risk of a breakdown).

## What is broken today

- `train.py` trains a `LogisticRegression` on `data/company.csv` but the whole
  thing is hard-coded: data path, model path, and knobs are not config-driven.
- It saves only `/app/model.joblib` — nothing reproducible is persisted: no
  plain numeric vector file, no experiment-data directory with config/metrics.
- The `years_review` coefficient is left sign-unconstrained.
- There is no held-out accuracy gate, so underfit models sail through.
- Splits use the RNG willy-nilly — folds are not reproducible.

A fresh dataset lives under `/app/data/company.csv` (evaluation rows in
`/app/data/val_company.csv`). At verification time a *fresh* dataset is mounted
somewhere else, so every data/output path and tuning knob must come from the
config so the trainer runs unchanged on the new data.

See the task instruction sheet (the `instruction.md` contract) for the exact
config keys, CLI overrides, output paths, and the products to persist.