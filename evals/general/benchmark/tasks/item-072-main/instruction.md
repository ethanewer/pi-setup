# Item-072 (medium) — fastText review classifier tuned under competing constraints

You are a machine-learning engineer at a review-analytics startup. Build a
**review-sentiment classifier** with fastText from a sample of Yelp-style
reviews, and tune it to satisfy **two competing constraints at once**:
accuracy high enough for the product, model small enough for on-device
distribution.

## What is already in the container

- `/app/data/train.parquet` — 15,000 training reviews. Two columns: `text`
  (the review, one sentence) and `stars` (integer 1..5).
- `/app/data/val.parquet` — 5,000 validation reviews, same schema. This is the
  held-out set you use to tune hyperparameters.
- python3 with `pandas`, `pyarrow`, `numpy`, and the `fasttext` package
  installed. Everything runs fully offline; do not download any data.

## Label rule (exact)

A review is **positive** if `stars >= 4`, **negative** otherwise
(`1 <= stars <= 3`). In fastText format each training line must be:
`__label__pos <review text>` or `__label__neg <review text>`.

## Required artifacts (exact paths and formats)

Produce exactly these, working anywhere you like under `/app`:

1. `/app/train.py` — your reproducible train/evaluate script. It must:
   - read `/app/data/train.parquet` and `/app/data/val.parquet`,
   - convert both to fastText text format (intermediate `.txt` files may live
     anywhere under `/app/`),
   - train a fastText supervised model with a **fixed, recorded seed**,
   - measure validation accuracy yourself,
   - write `/app/output/model.bin`, `/app/output/metrics.json`,
     `/app/output/sweep.json`.
   Running `python3 /app/train.py` from any directory must regenerate all three
   outputs **deterministically** (same seed ⇒ same accuracy within noise).

2. `/app/output/metrics.json` — a single JSON object with exactly these keys:
   `val_accuracy` (float 0..1), `model_size_bytes` (int, size of the final
   `model.bin`), `dim` (int), `bucket` (int), `minn` (int), `maxn` (int),
   `epoch` (int), `lr` (float), `wordNgrams` (int), `seed` (int).

3. `/app/output/sweep.json` — a JSON array of **at least 3** trained
   configurations, each entry an object with the same keys as `metrics.json`.
   This is your recorded tuning evidence: entries must be **sorted by
   `model_size_bytes` ascending**, have **strictly increasing distinct sizes**,
   and their `val_accuracy` values must **all lie within 0.02 of one another**
   (the point you are proving: accuracy survives while the model shrinks).
   The largest entry must be **at least 5x** the smallest entry's size (so the
   sweep is a real range, not noise).

4. `/app/output/model.bin` — the trained fastText model, loadable with
   `fasttext.load_model`, matching the **best** sweep entry.

## Competing constraints (the core of the task)

Pick hyperparameters so that at least one sweep entry satisfies **BOTH**:

- `val_accuracy >= 0.90`
- `model_size_bytes <= 2_000_000`

The **final model** (`model.bin` + `metrics.json`) must be the **smallest-size
sweep entry that satisfies both constraints**. If no entry satisfies both, the
final model must be the most accurate entry instead.

Default fastText parameters (dim=100, bucket=2000000, wordNgrams=2) produce a
model around **800 MB** — far over the 2 MB cap. You must deliberately reduce
`bucket` and/or `dim` (and optionally `minn`/`maxn`, `epoch`, `lr`,
`wordNgrams`) to fit the size cap while keeping accuracy at or above 0.90. The
data has ~6% label noise, so the achievable validation accuracy is
~0.93–0.94 (not 1.0); that keeps the accuracy bar real.

## Hints

- `pandas.read_parquet(...)`, write fastText lines yourself; `fasttext` takes a
  file path, not a buffer.
- `fasttext.train_supervised(path, dim=..., bucket=..., epoch=..., lr=...,
  minn=..., maxn=..., wordNgrams=..., seed=..., verbose=0)`.
- `model.save_model(".../model.bin")`; `os.path.getsize(...)` gives bytes.
- Compute `val_accuracy` on `/app/data/val.parquet`, not training-time output.
- Fix `seed` and keep every step deterministic.