# Cobalt Sonar — ticket triage classifier under a size budget

Cobalt Sonar routes inbound support tickets into three queues — `billing`,
`outage`, and `feature` — using a **fastText** text classifier. Your job is to
train the classifier so it clears both a **holdout accuracy bar** and a
**serialized model-size budget**, and to report the numbers honestly. The
trainer will be re-run by the router on fresh corpora, so it must be a real,
general program — not something tuned to one file.

## Environment

- Working directory `/app`. Provided (do not modify):
  - `/app/data/tickets.tsv` — the shipped labeled corpus, one row per line,
    `label<TAB>text`, labels `billing` / `outage` / `feature`.
  - `/app/gen_corpus.py` — the deterministic corpus generator (reference for
    the data format; hidden corpora come from the same generator).
- Python 3.12 with the `fasttext` module (fasttext-wheel 0.9.2, numpy 1.26.4)
  preinstalled. No network access.

## Deliverables (all three required)

1. `/app/train.py` — a runnable Python program with the interface:
   ```
   python3 /app/train.py <corpus_tsv> <outdir>
   ```
   It must parse the corpus, train a fastText supervised classifier, save the
   model, evaluate it, and write the report (see below). It must work on **any**
   corpus in the same format, and must be safely re-runnable (re-running with
   the same arguments overwrites its outputs cleanly).

2. `/app/model.bin` — the fastText model your trainer saves **when run on the
   shipped corpus**:
   ```
   python3 /app/train.py /app/data/tickets.tsv /app
   ```

3. `/app/report.json` — the report produced by the same visible run, with
   exactly these keys:
   ```json
   {
     "corpus_path": "<the corpus path exactly as passed on the command line>",
     "total_rows": <int>, "train_rows": <int>, "test_rows": <int>,
     "model_bytes": <int>, "holdout_accuracy": <float>
   }
   ```
   - `total_rows` — rows that survive corpus parsing (rules below).
   - `train_rows` / `test_rows` — the deterministic split counts.
   - `model_bytes` — the actual byte size of the saved `model.bin`.
   - `holdout_accuracy` — accuracy of the **saved** model on the test rows
     (0.0–1.0). The verifier re-measures everything; a report that does not
     match reality fails.

## Corpus parsing (the verifier implements exactly these rules)

Read the file line by line and:
1. Skip lines that are empty or whitespace-only.
2. Split each remaining line on the TAB character; a line that does not split
   into **exactly two** fields is skipped.
3. `label = field0.strip()`, `text = field1.strip()`. Skip the row if `label`
   is not one of `billing`, `outage`, `feature`, or if `text` is empty.
4. Everything else is a row.

## Deterministic holdout split (use exactly this)

With the **stripped** `text` of each parsed row:
```python
is_test = int(hashlib.sha256(text.encode("utf-8")).hexdigest(), 16) % 5 == 0
```
Rows with `is_test` form the holdout test set; all other rows are the training
set. Train on training rows only (e.g. written as `__label__<label> <text>`
lines, fastText convention), then evaluate the **saved** model on every test
row: a prediction is correct when `model.predict(text)[0][0]` equals
`__label__<label>`.

## Hard gates (checked on the visible corpus AND on hidden corpora)

- **Accuracy:** recomputed holdout accuracy of the saved model must be
  **>= 0.91**. An under-fit model (too few epochs / too small a capacity)
  will fall below the bar.
- **Size:** the serialized model file must be **<= 120000 bytes (120 KB)**.
  Note that a big `dim` or `wordNgrams > 1` inflates the serialized model
  dramatically (the bucket matrix is stored) — you must pick hyperparameters
  that satisfy *both* gates, e.g. by pruning/quantizing or choosing a smaller
  embedding dim.
- **Report honesty:** every report field must equal the verifier's own
  recomputation (`holdout_accuracy` within 0.005).

## Constraints

- The verifier re-runs `python3 /app/train.py <hidden_corpus> <fresh_outdir>`
  on hidden corpora (same format, different sizes, including one with
  malformed rows that must be skipped per the parsing rules) and applies all
  gates to the artifacts in `<fresh_outdir>`.
- Do not hard-code row counts or contents; do not write anything outside the
  given `<outdir>` (a temp training file inside `<outdir>` is fine, but
  `model.bin` and `report.json` are what count).
- Standard library + preinstalled `fasttext`/`numpy` only; no network.
