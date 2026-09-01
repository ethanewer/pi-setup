#!/bin/bash
# Oracle for saffron-mesa: author the fit-and-persist program per the contract,
# then RUN it on the visible corpus to produce /app/model_store/nb_model.pkl.
# Never reads /tests.
set -eu

mkdir -p /app/model_store

cat > /app/fit.py <<'PY'
import csv
import math
import pickle
import re
import sys


def tokenize(text):
    return re.findall(r"[a-z0-9]+", text.lower())


def fit(corpus_path):
    docs = []
    with open(corpus_path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            docs.append((row["text"], row["label"]))
    n = len(docs)
    classes = sorted(set(label for _, label in docs))
    vocab = sorted(set(t for text, _ in docs for t in tokenize(text)))

    counts = {c: {} for c in classes}
    totals = {c: 0 for c in classes}
    doc_counts = {c: 0 for c in classes}
    for text, label in docs:
        doc_counts[label] += 1
        for t in tokenize(text):
            counts[label][t] = counts[label].get(t, 0) + 1
            totals[label] += 1

    log_prior = {c: math.log(doc_counts[c] / n) for c in classes}
    log_likelihood = {}
    for c in classes:
        log_likelihood[c] = {
            t: math.log((counts[c].get(t, 0) + 1.0) / (totals[c] + len(vocab)))
            for t in vocab
        }
    return {
        "model_type": "multinomial_nb",
        "alpha": 1.0,
        "classes": classes,
        "vocab": vocab,
        "log_prior": log_prior,
        "log_likelihood": log_likelihood,
    }


def main():
    corpus_path, out_path = sys.argv[1], sys.argv[2]
    model = fit(corpus_path)
    with open(out_path, "wb") as fh:
        pickle.dump(model, fh)


if __name__ == "__main__":
    main()
PY

chmod +x /app/fit.py

python3 /app/fit.py /app/data/tickets.csv /app/model_store/nb_model.pkl

echo "solve.sh done"
ls -l /app/fit.py /app/model_store/nb_model.pkl
