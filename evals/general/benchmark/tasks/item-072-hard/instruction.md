# Item-072 (hard) — fastText review classifier on noisy, imbalanced data

You are a senior ML engineer. Build a **review-sentiment classifier** with
fastText from a noisy, **class-imbalanced** sample of Yelp-style reviews, and
deliver a model that is **small enough for a mobile app** while staying accurate
on **both** sentiment classes (not just the majority one).

## What is already in the container

- `/app/data/train.parquet` — 18,000 training reviews. Columns: `text`
  (one-sentence review), `stars` (integer 1..5). The data is **noisy (~14% of
  labels are flipped)** and **imbalanced**: roughly 36% positive / 64% negative.
- `/app/data/val.parquet` — 6,000 validation reviews, same schema
  (imbalanced too). Use it to tune.
- python3 with `pandas`, `pyarrow`, `numpy`, `fasttext`. Fully offline.

## Label rule (exact)

`stars >= 4` ⇒ positive (`__label__pos`); `stars <= 3` ⇒ negative
(`__label__neg`). Because of the imbalance, a model that always predicts the
majority class has **zero** positive-class recall — your model must genuinely
learn both classes.

## Required artifacts (exact paths and formats)

1. `/app/train.py` — reproducible train/evaluate script. Reads
   `/app/data/train.parquet` and `/app/data/val.parquet`, converts to fastText
   format, trains with a fixed recorded seed, measures validation metrics, and
   writes `/app/output/model.bin`, `/app/output/metrics.json`,
   `/app/output/sweep.json`. Running `python3 /app/train.py` from any directory
   must regenerate all three deterministically.

2. `/app/output/metrics.json` — single JSON object with keys `val_accuracy`
   (overall, 0..1), `pos_recall` (positive-class recall, 0..1), `neg_recall`
   (negative-class recall, 0..1), `model_size_bytes` (int, size of final
   `model.bin`), `dim`, `bucket`, `minn`, `maxn`, `epoch`, `lr`, `wordNgrams`,
   `seed`.

3. `/app/output/sweep.json` — JSON array of **at least 5** trained
   configurations, each entry with the **same keys as `metrics.json`**.
   Entries sorted by `model_size_bytes` ascending, with **strictly increasing
   distinct sizes**; the largest must be **at least 5x** the smallest; all
   `val_accuracy` values must lie **within 0.02 of one another** (accuracy
   survives while the model shrinks). This is your proof of the
   accuracy/size trade-off.

4. `/app/output/model.bin` — trained fastText model (`fasttext.load_model`
   -loadable) matching the final chosen sweep entry.

## Competing constraints (core of the task)

Choose hyperparameters so at least one sweep entry satisfies **ALL THREE**:

- `val_accuracy >= 0.86`
- `model_size_bytes <= 2_000_000`
- `pos_recall >= 0.78`

The **final model** must be the **smallest-size sweep entry satisfying all
three**. If none does, fall back to the most accurate entry.

fastText defaults (dim=100, bucket=2000000) produce an ~800 MB model — far over
the 2 MB cap. You must deliberately reduce `bucket`/`dim` (and optionally other
args) to fit. Because labels are noisy (~14%) and the positive class is the
minority, the achievable overall validation accuracy is ~0.87 with positive
recall around 0.79–0.80 on this data — so the accuracy bar is deliberately not
1.0.

## Hints

- `pandas.read_parquet`, write fastText lines yourself; `fasttext` takes file
  paths.
- `fasttext.train_supervised(path, dim=..., bucket=..., epoch=..., lr=...,
  minn=..., maxn=..., wordNgrams=..., seed=..., verbose=0)`.
- Compute `val_accuracy`, `pos_recall`, `neg_recall` yourself on
  `/app/data/val.parquet`; don't trust training-time output.
- Fix `seed`; keep every step deterministic.