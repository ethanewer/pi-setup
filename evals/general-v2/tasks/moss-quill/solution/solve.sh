#!/bin/bash
# Oracle for moss-quill: author the trainer (the deliverable program), then
# RUN it on the shipped visible corpus to produce /app/model.pkl and
# /app/report.json. Never reads /tests.
set -eu

cat > /app/train.py <<'PY'
"""moss-quill trainer: fasttext-style linear classifier under a size budget."""
import hashlib
import json
import os
import sys

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline

BUDGET_BYTES = 262144


def read_corpus(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or "\t" not in line:
                continue
            lab, _, txt = line.partition("\t")
            lab, txt = lab.strip(), txt.strip()
            if not lab or not txt:
                continue
            rows.append((lab, txt))
    return rows


def holdout_split(rows):
    train, test = [], []
    for lab, txt in rows:
        h = int(hashlib.sha256(txt.encode("utf-8")).hexdigest(), 16)
        (test if h % 5 == 0 else train).append((lab, txt))
    return train, test


def main():
    corpus = sys.argv[1] if len(sys.argv) > 1 else "/app/data/tickets.tsv"
    out_model = sys.argv[2] if len(sys.argv) > 2 else "/app/model.pkl"
    out_report = sys.argv[3] if len(sys.argv) > 3 else "/app/report.json"

    rows = read_corpus(corpus)
    assert rows, "no usable rows in %s" % corpus
    train, test = holdout_split(rows)
    assert train and test, "degenerate holdout split"

    # Linear bag-of-ngrams classifier. The vocabulary is deliberately
    # bounded (min_df=2, max_features=4000, bigrams kept) so the serialized
    # pipeline fits the 262144-byte budget while generalizing past the
    # accuracy floor; the unbounded variant pickles to ~350 KB.
    clf = Pipeline([
        ("features", TfidfVectorizer(ngram_range=(1, 2), min_df=2,
                                     max_features=4000, sublinear_tf=True)),
        ("linear", LogisticRegression(C=20.0, max_iter=2000)),
    ])
    clf.fit([t for _, t in train], [l for l, _ in train])

    pred = clf.predict([t for _, t in test])
    truth = [l for l, _ in test]
    acc = sum(str(p) == l for p, l in zip(pred, truth)) / len(test)

    import pickle
    with open(out_model, "wb") as fh:
        pickle.dump(clf, fh)

    report = {
        "train_rows": len(train),
        "test_rows": len(test),
        "holdout_accuracy": acc,
        "model_bytes": os.path.getsize(out_model),
        "budget_bytes": BUDGET_BYTES,
        "labels": sorted({l for l, _ in rows}),
    }
    with open(out_report, "w") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps(report))


if __name__ == "__main__":
    main()
PY
chmod +x /app/train.py

# Run the trainer on the shipped visible corpus to produce the artifacts.
python3 /app/train.py /app/data/tickets.tsv /app/model.pkl /app/report.json

echo "solve.sh done -> /app/train.py /app/model.pkl /app/report.json"
wc -c /app/train.py /app/model.pkl /app/report.json
