#!/bin/bash
# Oracle for cobalt-sonar: write the trainer program (the real work — it must
# hit the holdout accuracy bar and the serialized-size budget), then run it on
# the shipped corpus to produce /app/model.bin and /app/report.json.
# Never reads /tests.
set -eu
mkdir -p /app

cat > /app/train.py <<'PY'
import hashlib
import json
import os
import sys

import fasttext

LABELS = ("billing", "outage", "feature")


def read_rows(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                continue
            label, text = parts[0].strip(), parts[1].strip()
            if label not in LABELS or not text:
                continue
            rows.append((label, text))
    return rows


def is_test(text):
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest(), 16) % 5 == 0


def main():
    corpus, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    rows = read_rows(corpus)
    train = [(l, t) for l, t in rows if not is_test(t)]
    test = [(l, t) for l, t in rows if is_test(t)]

    train_file = os.path.join(outdir, ".train.tmp.txt")
    with open(train_file, "w", encoding="utf-8") as fh:
        for label, text in train:
            fh.write("__label__%s %s\n" % (label, text))

    # dim 50 clears the accuracy bar while the serialized model stays
    # far inside the 120 KB budget.
    model = fasttext.train_supervised(
        input=train_file, dim=50, epoch=25, lr=0.5, wordNgrams=1, thread=1,
    )
    model_path = os.path.join(outdir, "model.bin")
    model.save_model(model_path)
    os.remove(train_file)

    # evaluate the SAVED model on the deterministic holdout
    loaded = fasttext.load_model(model_path)
    correct = 0
    for label, text in test:
        if loaded.predict(text)[0][0] == "__label__" + label:
            correct += 1
    acc = (correct / len(test)) if test else 0.0

    report = {
        "corpus_path": corpus,
        "total_rows": len(rows),
        "train_rows": len(train),
        "test_rows": len(test),
        "model_bytes": os.path.getsize(model_path),
        "holdout_accuracy": round(acc, 4),
    }
    with open(os.path.join(outdir, "report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
    print("report:", report)


if __name__ == "__main__":
    main()
PY

chmod +x /app/train.py
python3 /app/train.py /app/data/tickets.tsv /app

echo "solve.sh done"
ls -l /app/train.py /app/model.bin /app/report.json
