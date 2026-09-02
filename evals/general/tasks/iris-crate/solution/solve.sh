#!/bin/bash
# Oracle for iris-crate: write the real trainer (fasttext-style hashed
# n-gram softmax, pure stdlib), then run it on the shipped depot corpus to
# produce /app/model.bin and /app/metrics.json. Never reads /tests.
set -eu

cat > /app/train.py <<'PY'
"""Relayline depot triage trainer: fasttext-style hashed n-gram softmax."""
import json
import math
import pickle
import random
import re
import sys
import zlib

NBUCKETS = 65536
TOKEN = re.compile(r"[a-z0-9]+")


def features(text):
    toks = TOKEN.findall(text.lower())
    grams = toks + [toks[i] + "\x1f" + toks[i + 1]
                    for i in range(len(toks) - 1)]
    return [zlib.crc32(g.encode("utf-8")) % NBUCKETS for g in grams]


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if "\t" not in line:
                continue
            lab, _, txt = line.partition("\t")
            lab, txt = lab.strip(), txt.strip()
            if not lab or not txt:
                continue
            rows.append((lab, txt))
    return rows


def fit_on(rows, epochs=12, lr=0.5):
    labels = sorted({lab for lab, _ in rows})
    K = len(labels)
    idx = {l: i for i, l in enumerate(labels)}
    W = {}
    bias = [0.0] * K
    rng = random.Random(1234)
    order = list(range(len(rows)))
    for _e in range(epochs):
        rng.shuffle(order)
        for r in order:
            lab, txt = rows[r]
            F = features(txt)
            n = max(1, len(F))
            scores = bias[:]
            for f in F:
                wv = W.get(f)
                if wv is not None:
                    for j in range(K):
                        scores[j] += wv[j] / n
            mx = max(scores)
            exps = [math.exp(s - mx) for s in scores]
            z = sum(exps)
            y = idx[lab]
            for j in range(K):
                err = exps[j] / z - (1.0 if j == y else 0.0)
                bias[j] -= lr * err
                step = lr * err / n
                for f in F:
                    wv = W.get(f)
                    if wv is None:
                        wv = [0.0] * K
                        W[f] = wv
                    wv[j] -= step
    return labels, bias, W


def predict(labels, bias, W, text):
    K = len(labels)
    F = features(text)
    n = max(1, len(F))
    scores = bias[:]
    for f in F:
        wv = W.get(f)
        if wv is not None:
            for j in range(K):
                scores[j] += wv[j] / n
    best = 0
    for j in range(1, K):
        if scores[j] > scores[best]:
            best = j
    return labels[best]


def main():
    train_path, model_out, metrics_out = sys.argv[1], sys.argv[2], sys.argv[3]
    rows = read_rows(train_path)
    if not rows:
        raise SystemExit("no well-formed training rows")

    # the shipped model is fit on ALL well-formed rows; the self-reported
    # holdout_accuracy comes from a separate deterministic 80/20 split model
    rng = random.Random(99)
    idxs = list(range(len(rows)))
    rng.shuffle(idxs)
    cut = max(1, int(0.8 * len(rows)))
    tr = [rows[i] for i in idxs[:cut]]
    ho = [rows[i] for i in idxs[cut:]]

    labels, bias, W = fit_on(rows)
    mlabels, mbias, mW = fit_on(tr)
    correct = sum(1 for lab, txt in ho
                  if predict(mlabels, mbias, mW, txt) == lab)
    self_acc = correct / max(1, len(ho))

    pruned = {}
    for f, wv in W.items():
        if max(abs(v) for v in wv) >= 1e-4:
            pruned[f] = [round(v, 4) for v in wv]
    model = {"labels": labels,
             "bias": [round(b, 4) for b in bias],
             "w": pruned}
    blob = pickle.dumps(model)
    with open(model_out, "wb") as fh:
        fh.write(blob)
    json.dump({"holdout_accuracy": round(self_acc, 4),
               "train_rows": len(rows),
               "model_bytes": len(blob),
               "labels": labels},
              open(metrics_out, "w"), indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x /app/train.py
python3 /app/train.py /app/data/train.tsv /app/model.bin /app/metrics.json
cat /app/metrics.json
python3 - <<'PY'
import os
size = os.path.getsize("/app/model.bin")
assert size <= 2097152, "oracle model over budget: %d" % size
print("model_bytes =", size)
PY

echo "iris-crate oracle done"
