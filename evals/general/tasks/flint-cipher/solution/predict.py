#!/usr/bin/env python3
"""Classify documents with a saved /app/classifier_snapshot.npz.

Reads a label+document tsv (or lines of bare text) and writes one predicted
label per input line. Predictions come purely from the frozen snapshot; the
feature representation must match the one used at snapshot/training time.

Usage:
  python3 /app/predict.py [snapshot.npz] [input.tsv] [output.txt]
If output.txt is omitted, predictions are printed to stdout.
"""
import os
import re
import sys

import numpy as np


def doc_to_ngrams(text: str, nmin=2, nmax=4):
    clean = re.sub(r"[^a-z]+", " ", text.lower())
    grams = set()
    for n in range(nmin, nmax + 1):
        for i in range(len(clean) - n + 1):
            g = clean[i:i + n]
            if len(g) == n and " " not in g:
                grams.add(g)
    return grams


def main(argv):
    snapshot = argv[1] if len(argv) > 1 else "/app/classifier_snapshot.npz"
    inpath = argv[2] if len(argv) > 2 else "/app/data/dev.tsv"
    outpath = argv[3] if len(argv) > 3 else None

    if not os.path.exists(snapshot):
        print("ERROR: snapshot not found: %s" % snapshot, file=sys.stderr)
        return 2

    data = np.load(snapshot, allow_pickle=True)
    feature_index = [str(x) for x in data["feature"]]
    classes = [str(x) for x in data["classes"]]
    coef = data["coef"]
    intercept = data["intercept"]
    pos = {f: i for i, f in enumerate(feature_index)}

    rows = []
    with open(inpath, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            if "\t" in line:
                rows.append(line.split("\t", 1)[1])
            else:
                rows.append(line)

    preds = []
    for text in rows:
        if not text.strip():
            preds.append(np.argmax(intercept))  # no signal, use decision bias
            continue
        X = np.zeros((1, len(feature_index)), dtype=np.float32)
        for g in doc_to_ngrams(text):
            p = pos.get(g)
            if p is not None:
                X[0, p] += 1
        scores = X @ coef.T + intercept
        preds.append(int(np.argmax(scores[0])))

    lines_out = [classes[p] for p in preds]
    if outpath:
        with open(outpath, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines_out) + "\n")
    else:
        sys.stdout.write("\n".join(lines_out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))