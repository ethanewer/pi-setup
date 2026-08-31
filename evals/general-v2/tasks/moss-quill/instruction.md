# Moss-Quill helpdesk — triage model under an accuracy floor and a size budget

The Moss-Quill helpdesk routes support tickets into three queues — `billing`,
`bug`, and `howto` — with a fasttext-style classifier: a **linear model over
count/tf-idf text features** (bag of words / n-grams), i.e. the classic
"linear bag of n-grams" fastText recipe, no deep network involved.

Routing is on-device, so the serialized classifier must stay tiny, while the
helpdesk SLA requires it to be accurate. Your job: **train a classifier that
clears the holdout accuracy floor of 0.91 while its serialized size stays
within a 262144-byte budget.** A lazy full-vocabulary bigram model blows the
budget; a heavily truncated vocabulary drifts under the accuracy floor. The
art is in the middle.

## What is provided (do not modify)

* `/app/data/tickets.tsv` — the labeled training corpus: one ticket per line,
  `label<TAB>text`, labels `billing` / `bug` / `howto`.
* `/app/gen_tickets.py` — the deterministic corpus generator (the plant uses
  the same recipe for its evaluation corpora).

Work only under `/app`. CPU-only, no network.

## Deliverables (all required)

### 1. `/app/train.py` — the trainer

```
python3 /app/train.py [CORPUS_TSV] [OUT_MODEL] [OUT_REPORT]
```

With no arguments it defaults to `CORPUS_TSV=/app/data/tickets.tsv`,
`OUT_MODEL=/app/model.pkl`, `OUT_REPORT=/app/report.json`. With all three
arguments it must process **any corpus in the same format** and write the
model and report to the given paths (the plant calls it this way on fresh
corpora).

### 2. `/app/model.pkl` — the fitted classifier

A pickled object with a `.predict(list_of_text_strings)` method that returns
the predicted label strings. A fitted `sklearn.pipeline.Pipeline` (e.g.
`TfidfVectorizer`/`CountVectorizer` + linear classifier) satisfies this
directly. It must be loadable with plain `pickle.load` in an environment that
has scikit-learn.

### 3. `/app/report.json` — the training report

JSON with exactly these keys:

```json
{"train_rows": <int>, "test_rows": <int>, "holdout_accuracy": <float>,
 "model_bytes": <int>, "budget_bytes": 262144,
 "labels": ["billing", "bug", "howto"]}
```

- `train_rows` / `test_rows` — row counts of your train/test split.
- `holdout_accuracy` — your measured accuracy on the test split.
- `model_bytes` — the byte size of the model file you wrote.
- `budget_bytes` — always `262144`.
- `labels` — the **sorted** set of distinct labels in the corpus.

## The deterministic holdout (used identically by the plant)

Parse the corpus, skipping in order: lines that are blank or whitespace-only,
lines containing no TAB, and rows whose label or text is empty after
stripping. For each kept row, strip both fields; then assign it to the **test
split** if and only if

```python
int(hashlib.sha256(text.encode("utf-8")).hexdigest(), 16) % 5 == 0
```

where `text` is the **stripped** text field. All other rows are training
rows. The plant recomputes this exact split, so your report must agree with
it. Train only on the training rows; report accuracy only on the test rows.

## Hard requirements (all verified by the plant)

1. **Accuracy floor** — the classifier reaches holdout accuracy **>= 0.91**
   on the shipped corpus, computed with the split above.
2. **Size budget** — the serialized `/app/model.pkl` is **<= 262144 bytes**.
3. **Real training** — the model must be genuinely fitted on the corpus
   training rows (linear model over text-derived features), not a lookup of
   the split or any hash of the text.
4. **Report integrity** — every field of `/app/report.json` matches what the
   plant recomputes (`model_bytes` equals the actual file size on disk).
5. **Re-runnability** — `python3 /app/train.py <corpus> <model> <report>`
   works on any corpus in the shipped format, including ones with blank
   lines, rows without a TAB, punctuation-only texts, duplicate rows, and
   unusual whitespace. Such malformed rows are skipped by the parsing rule
   above; the rest must still train and clear the plant's per-corpus floors.
6. **Deterministic** — no reliance on wall-clock or randomness with unset
   seeds; repeated runs on the same corpus yield the same model.

## What the plant re-runs

The plant re-runs `/app/train.py` unchanged on hidden corpora built from the
same generator recipe (a fresh domain mix, and an edge corpus with malformed
rows) and re-checks: accuracy against that corpus's own floor, the size
budget, and full report integrity. A trainer hard-wired to the shipped file's
contents, or an under-fit model tuned only to scrape past the visible floor,
will fail.

## Sanity check

```python
import hashlib, pickle
rows = []
for line in open("/app/data/tickets.tsv"):
    line = line.rstrip("\n")
    if not line.strip() or "\t" not in line: continue
    lab, _, txt = line.partition("\t")
    lab, txt = lab.strip(), txt.strip()
    if lab and txt: rows.append((lab, txt))
test = [(l, t) for l, t in rows if int(hashlib.sha256(t.encode()).hexdigest(), 16) % 5 == 0]
clf = pickle.load(open("/app/model.pkl", "rb"))
pred = clf.predict([t for _, t in test])
print(sum(str(p) == l for p, l in zip(pred, [l for l, _ in test])) / len(test))
```
