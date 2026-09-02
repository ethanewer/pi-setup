#!/usr/bin/env python3
"""Train a tiny multilingual character classifier on CPU and persist a snapshot.

Learns a char n-gram logistic model over the training documents, evaluates it
on a held-out development split, and persists two artifacts:
  * classifier_snapshot.npz  -> features list, classes, coef, intercept
  * eval_metrics.json        -> overall + per-language accuracy on dev
The feature list is stored in the snapshot so /app/predict.py can classify
brand-new documents using exactly the same representation.
"""
import argparse
import json
import re

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import LabelEncoder

RNG_MIN, RNG_MAX = 2, 4


def doc_to_ngrams(text: str, nmin=RNG_MIN, nmax=RNG_MAX):
    """Multiset (dict) of char n-grams present in a lower-cased document."""
    clean = re.sub(r"[^a-z]+", " ", text.lower())
    out = {}
    for n in range(nmin, nmax + 1):
        for i in range(len(clean) - n + 1):
            g = clean[i:i + n]
            if len(g) == n and " " not in g:
                out[g] = out.get(g, 0) + 1
    return out


def read_rows(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if "\t" in line:
                label, text = line.split("\t", 1)
            else:
                label, text = "unknown", line
            rows.append((label, text))
    return rows


def build_matrix(rows, feature_index):
    pos = {f: i for i, f in enumerate(feature_index)}
    X = np.zeros((len(rows), len(feature_index)), dtype=np.float32)
    for r, (_, text) in enumerate(rows):
        for g, c in doc_to_ngrams(text).items():
            p = pos.get(g)
            if p is not None:
                X[r, p] = c
    return X


def evaluate(clf, le, rows, feature_index):
    X = build_matrix(rows, feature_index)
    pred = clf.predict(X)
    true = le.transform([lbl for lbl, _ in rows])
    acc = float((pred == true).mean())
    per = {}
    for idx, cls in enumerate(le.classes_):
        mask = true == idx
        per[str(cls)] = float((pred[mask] == idx).mean()) if mask.sum() else 0.0
    return acc, per


def main() -> int:
    ap = argparse.ArgumentParser(
        description="train a multilingual char-n-gram classifier")
    ap.add_argument("--train", required=True)
    ap.add_argument("--dev", required=True)
    ap.add_argument("--snapshot", default="/app/classifier_snapshot.npz")
    ap.add_argument("--metrics", default="/app/eval_metrics.json")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    train = read_rows(args.train)
    dev = read_rows(args.dev)

    feature_set = set()
    for _, text in train:
        feature_set.update(doc_to_ngrams(text))
    feature_index = sorted(feature_set)
    assert len(feature_index) <= 20000, "feature set unexpectedly large"

    X_train = build_matrix(train, feature_index)
    le = LabelEncoder()
    y_train = le.fit_transform([lbl for lbl, _ in train])

    clf = LogisticRegression(solver="lbfgs", max_iter=2000, C=10.0,
                             random_state=args.seed)
    clf.fit(X_train, y_train)

    dev_acc, dev_per = evaluate(clf, le, dev, feature_index)

    np.savez_compressed(
        args.snapshot,
        feature=np.array(feature_index),           # unicode array
        classes=np.array([str(c) for c in le.classes_]),
        coef=clf.coef_.astype(np.float32),
        intercept=clf.intercept_.astype(np.float32),
    )

    metrics = {
        "overall_accuracy": round(dev_acc, 4),
        "per_language": {k: round(v, 4) for k, v in dev_per.items()},
        "train_size": len(train),
        "n_features": len(feature_index),
    }
    with open(args.metrics, "w", encoding="utf-8") as fh:
        json.dump(metrics, fh, indent=2, sort_keys=True)
    print(json.dumps(metrics, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())