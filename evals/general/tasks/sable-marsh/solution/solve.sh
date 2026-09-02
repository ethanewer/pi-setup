#!/bin/bash
# Oracle for sable-marsh: write the fit_model.py program (the real work), then
# RUN it on the shipped site data to produce the registered artifacts. Never
# reads /tests.
set -eu

cat > /app/fit_model.py <<'PY'
import csv
import json
import os
import sys

import joblib
from sklearn.linear_model import LogisticRegression

FLOOR = 0.80
TARGET = "fault"


def load_split(path):
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        raise ValueError("empty table: %s" % path)
    header = rows[0]
    if TARGET not in header:
        raise ValueError("missing target column %r in %s" % (TARGET, path))
    feats = [c for c in header if c != TARGET]
    tidx = header.index(TARGET)
    fidx = [i for i in range(len(header)) if i != tidx]
    X, y = [], []
    for lineno, row in enumerate(rows[1:], start=2):
        if len(row) != len(header):
            raise ValueError("row %d has %d fields, want %d" % (lineno, len(row), len(header)))
        try:
            X.append([float(row[i]) for i in fidx])
            y.append(int(float(row[tidx])))
        except ValueError as exc:
            raise ValueError("non-numeric cell at row %d: %s" % (lineno, exc)) from exc
    if not X:
        raise ValueError("no data rows in %s" % path)
    return feats, X, y


def main():
    train_csv, holdout_csv, model_out, manifest_out = sys.argv[1:5]
    try:
        feats, X, y = load_split(train_csv)
        _, Xh, yh = load_split(holdout_csv)
    except (OSError, ValueError) as exc:
        print("input error: %s" % exc, file=sys.stderr)
        return 2
    if len(feats) != len(Xh[0]):
        print("input error: train/holdout feature counts differ", file=sys.stderr)
        return 2

    model = LogisticRegression(max_iter=1000, random_state=42)
    model.fit(X, y)
    acc = float(model.score(Xh, yh))
    if acc < FLOOR:
        print("accuracy %.4f below floor %.2f" % (acc, FLOOR), file=sys.stderr)
        return 3

    for out in (model_out, manifest_out):
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    joblib.dump(model, model_out)
    manifest = {
        "n_features": len(feats),
        "feature_columns": feats,
        "target": TARGET,
        "holdout_accuracy": acc,
    }
    with open(manifest_out, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print("registered model: n_features=%d holdout_accuracy=%.4f" % (len(feats), acc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/fit_model.py

python3 /app/fit_model.py /app/data/site_a.csv /app/data/site_b.csv \
    /app/artifacts/model.joblib /app/artifacts/manifest.json

echo "solve.sh done"
ls -l /app/fit_model.py /app/artifacts/model.joblib /app/artifacts/manifest.json
