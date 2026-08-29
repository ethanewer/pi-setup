#!/usr/bin/env python3
"""kayak-qa -- binding-affinity model trainer (rank-accuracy gate).

Loads a descriptor matrix and a set of measured binding-affinity values, fits a
regression pipeline on a random train/holdout split, and reports the Spearman
rank correlation between predictions and measurements on the held-out test
rows, repeated across several independent random seeds.

The relationship between descriptors and affinity is NOT given: the trainer is
expected to learn it from data (this is the point of the gate).  A model that
seriously under-fits, or that fails to find the informative descriptors, cannot
clear the threshold on held-out rows.

CLI:
    python3 train_affinity.py --descriptors X.npy --targets y.npy \\
        [--n_seeds 8] [--threshold 0.9] [--out report.json]
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from scipy.stats import spearmanr


def run_pipeline(descriptors, targets, n_seeds=8):
    """Train and score on held-out rows across `n_seeds` seeds."""
    X = np.asarray(descriptors, dtype=float)
    y = np.asarray(targets, dtype=float)
    n = X.shape[0]
    if y.shape[0] != n:
        raise ValueError(
            "dimension mismatch: descriptors (%d rows) vs targets (%d rows)"
            % (n, y.shape[0]))

    idx = np.arange(n)
    threshold = 0.9
    seed_rows = []
    for s in range(int(n_seeds)):
        if n < 4:
            raise ValueError("dataset too small to split (%d rows)" % n)
        tr_ix, te_ix = train_test_split(idx, test_size=0.2, random_state=int(s))
        Xtr, Xte = X[tr_ix], X[te_ix]
        ytr, yte = y[tr_ix], y[te_ix]
        model = RandomForestRegressor(
            n_estimators=300, min_samples_leaf=2, random_state=int(s),
            n_jobs=1)
        model.fit(Xtr, ytr)
        pred = model.predict(Xte)
        sp = float(spearmanr(yte, pred).correlation)
        seed_rows.append({
            "seed": int(s),
            "n_train": int(len(tr_ix)),
            "test_size": int(len(te_ix)),
            "spearman": round(sp, 6),
            "test_ids": [int(i) for i in te_ix],
            "test_pred": [float(v) for v in pred],
        })

    all_pass = all(r["spearman"] >= threshold for r in seed_rows)
    return {
        "descriptor_columns": int(X.shape[1]),
        "n_rows": n,
        "n_seeds": int(n_seeds),
        "threshold": threshold,
        "test_fraction": 0.2,
        "all_pass": bool(all_pass),
        "min_spearman": round(min(r["spearman"] for r in seed_rows), 6),
        "seeds": seed_rows,
    }


def main(argv: Optional[list] = None) -> int:
    ap = argparse.ArgumentParser(description="Train affinity model, report rank accuracy.")
    ap.add_argument("--descriptors", required=True)
    ap.add_argument("--targets", required=True)
    ap.add_argument("--n_seeds", type=int, default=8)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    try:
        X = np.load(args.descriptors)
        y = np.load(args.targets)
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1

    try:
        report = run_pipeline(X, y, n_seeds=args.n_seeds)
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())