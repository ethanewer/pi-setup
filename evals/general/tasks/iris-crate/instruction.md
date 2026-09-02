# Relayline depot — fasttext-style ticket triage under a size budget

Relayline runs a freight-depot helpdesk. Inbound tickets must be triaged into
four queues: `BILLING`, `DAMAGES`, `RETURNS`, `TRACKING`. You will build and
train a **fasttext-style text classifier** (hashed n-gram bag + linear layer)
that clears a holdout accuracy floor while the serialized model stays under a
hard size budget. Training is pure CPU, standard library only, no network.

## Provided (do not modify)

* `/app/gen_tickets.py` — the deterministic depot corpus generator.
* `/app/data/train.tsv` — 4000 labeled tickets, one per line:
  `LABEL<TAB>text` (labels are the four queue names).
* `/app/data/holdout.tsv` — 1000 labeled tickets, a **sealed QA holdout**.
  You may use it to sanity-check your model, but it is *evaluation data*:
  your trainer must **fit only on the training file it is given**.

## Deliverables (all three required)

1. `/app/train.py` — the trainer:
   ```
   python3 /app/train.py <train_tsv> <model_out> <metrics_out>
   ```
   It fits a classifier on `<train_tsv>` **only** and writes the model and a
   metrics report. It must work on **any** corpus in the same format (the QA
   rig re-runs it on fresh corpora, including ones with malformed rows).

2. `/app/model.bin` — the model produced by
   ```
   python3 /app/train.py /app/data/train.tsv /app/model.bin /app/metrics.json
   ```

3. `/app/metrics.json` — the metrics report for that run:
   ```json
   { "holdout_accuracy": 0.91, "train_rows": 4000,
     "model_bytes": 601234, "labels": ["BILLING", "DAMAGES", "RETURNS", "TRACKING"] }
   ```
   * `holdout_accuracy` — a genuine held-out accuracy estimate computed by
     your trainer (e.g. on its own deterministic split of the training rows);
     it must lie in `[0, 1]`.
   * `train_rows` — number of well-formed training rows consumed.
   * `model_bytes` — the **actual byte size** of the written model file.
   * `labels` — the sorted distinct training labels; must equal the model's.

## Model format (a pinned pickle contract)

`model_out` is a `pickle` of a dict with **exactly** these keys:

```python
{
  "labels": [...],           # sorted class names (strings)
  "bias":   [...],           # one float per class
  "w":      {bucket: [...]}, # int bucket -> one float per class
}
```

Missing buckets are treated as all-zero. The QA rig scores the model with
this exact, documented inference rule:

* Tokenize: lowercase the text, tokens are the runs of `[a-z0-9]+`.
* Grams: every token (unigram) **and** every adjacent bigram
  `tok[i] + "\x1f" + tok[i+1]` (empty token list -> no grams).
* Bucket of a gram: `zlib.crc32(gram.encode("utf-8")) % 65536`; the feature
  list `F` keeps multiplicity (one entry per gram occurrence).
* `score_j = bias[j] + (sum over f in F of w[f][j]) / max(1, len(F))`
  (buckets absent from `w` contribute 0).
* Predict `labels[j]` for the largest `score_j`; ties break to the **smallest
  index** (i.e. first in sorted order).

## Budgets and floors (hard gates)

* **Accuracy floor:** the model must reach **>= 0.88 accuracy** on the depot's
  sealed holdout (and >= 0.85 / 0.80 on the fresh / adversarial hidden
  corpora the rig uses). An under-fit model — too few epochs, a mis-set
  learning rate, unigrams only on a noisy mix, no training at all — falls
  below the floor.
* **Size budget:** the serialized model file must be **<= 2097152 bytes
  (2 MiB)**. Do not ship the training data or anything that is not the
  documented model dict; round or prune weights if you need headroom.
* **Robustness:** malformed rows must be skipped, never crash the trainer:
  blank lines, lines without a TAB, rows whose label or text strips to empty.

## Constraints

* Deterministic: seed any randomness; the same input must yield a working
  model on every run. Standard library only; no network at run or verify.
* The rig re-runs `/app/train.py` unchanged on hidden corpora (same format,
  different seeds and mixes) and scores the produced model with the
  documented inference rule against that corpus's sealed holdout.
* Do not modify `/app/gen_tickets.py`, `/app/data/train.tsv`, or
  `/app/data/holdout.tsv`.
