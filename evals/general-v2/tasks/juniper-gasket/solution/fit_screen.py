#!/usr/bin/env python3
"""
juniper-gasket: fit a contamination screener that meets the accuracy floor.

  python3 fit_screen.py <casedir> <outdir>     (defaults: /app/case /app)

<casedir> holds train.csv, test.csv and meta.json (features, target,
accuracy_floor). <outdir> receives:
  screen_model.pkl    - the fitted scikit-learn model (pickle, has .predict)
  screen_metrics.json - holdout accuracy, floor, and pass flag
"""
import argparse
import json
import os
import pickle
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("casedir", nargs="?", default="/app/case")
    ap.add_argument("outdir", nargs="?", default="/app")
    args = ap.parse_args()
    case, outdir = args.casedir, args.outdir
    os.makedirs(outdir, exist_ok=True)

    meta = json.load(open(os.path.join(case, "meta.json")))
    features = meta["features"]
    target = meta["target"]
    floor = float(meta["accuracy_floor"])

    train = pd.read_csv(os.path.join(case, "train.csv"))
    test = pd.read_csv(os.path.join(case, "test.csv"))

    for col in features + [target]:
        if col not in train.columns or col not in test.columns:
            print("missing required column %s" % col, file=sys.stderr)
            sys.exit(2)

    Xtr = train[features].to_numpy(dtype=np.float64)
    ytr = train[target].to_numpy(dtype=np.int64)
    Xte = test[features].to_numpy(dtype=np.float64)
    yte = test[target].to_numpy(dtype=np.int64)

    model = Pipeline([
        ("scaler", StandardScaler()),
        ("clf", LogisticRegression(C=1.0, max_iter=1000, random_state=0)),
    ])
    model.fit(Xtr, ytr)

    acc = float(model.score(Xte, yte))
    metrics = {
        "case_id": meta["case_id"],
        "test_accuracy": round(acc, 4),
        "accuracy_floor": floor,
        "meets_floor": bool(acc >= floor),
    }
    with open(os.path.join(outdir, "screen_model.pkl"), "wb") as f:
        pickle.dump(model, f)
    with open(os.path.join(outdir, "screen_metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print("[fit] test accuracy %.4f vs floor %.2f -> meets_floor=%s"
          % (acc, floor, metrics["meets_floor"]))
    if not metrics["meets_floor"]:
        sys.exit(3)


if __name__ == "__main__":
    main()
