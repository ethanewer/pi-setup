#!/bin/bash
# Real oracle for cobalt-tide: write the train_yield.py program (this IS the
# work: a tuned nonlinear ensemble that clears the strict held-out Spearman
# gate), then RUN it on the visible fixtures to produce /app/yield_report.json.
# Never reads /tests.
set -eu

PROGRAM="/app/train_yield.py"
REPORT="/app/yield_report.json"

cat > "$PROGRAM" <<'PY'
#!/usr/bin/env python3
"""cobalt-tide -- wafer-yield rank-accuracy gate trainer.

Repeats, over `n_seeds` independent random splits: fit on the train rows,
predict the held-out rows, and record the Spearman rank correlation between
predictions and the measured yield on exactly those rows.  The gate requires
every seed's held-out Spearman to clear the threshold.

CLI:
    python3 train_yield.py --features X.npy --target y.npy \\
        --n_seeds 10 --threshold 0.92 --out report.json
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

import numpy as np
from scipy.stats import spearmanr
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import train_test_split


def build_model(seed: int):
    # The process response is strongly nonlinear (smooth wiggles + pairwise
    # interactions + a Gaussian-bump term). A histogram gradient-boosting
    # ensemble with enough rounds, a small learning rate and a mild L2 penalty
    # tracks it closely on held-out rows; linear models and untuned random
    # forests under-fit badly on data of this form.
    return HistGradientBoostingRegressor(
        max_iter=400,
        learning_rate=0.06,
        max_leaf_nodes=31,
        min_samples_leaf=15,
        l2_regularization=1.0,
        early_stopping=False,
        random_state=int(seed),
    )


def run_pipeline(features, targets, n_seeds=10, threshold=0.92,
                 test_fraction=0.2):
    X = np.asarray(features, dtype=float)
    y = np.asarray(targets, dtype=float).ravel()
    n = X.shape[0]
    if y.shape[0] != n:
        raise ValueError(
            "shape mismatch: features has %d rows but target has %d rows"
            % (n, y.shape[0]))
    if n < 10:
        raise ValueError("dataset too small to form a holdout (%d rows)" % n)

    frac = float(min(0.3, max(0.1, test_fraction)))
    idx = np.arange(n)
    threshold = float(threshold)
    seed_rows = []
    for s in range(int(n_seeds)):
        tr_ix, te_ix = train_test_split(
            idx, test_size=frac, random_state=int(s))
        model = build_model(s)
        model.fit(X[tr_ix], y[tr_ix])
        pred = model.predict(X[te_ix])
        sp = float(spearmanr(y[te_ix], pred).correlation)
        seed_rows.append({
            "seed": int(s),
            "n_train": int(len(tr_ix)),
            "test_size": int(len(te_ix)),
            "spearman": round(sp, 6),
            "test_ids": [int(i) for i in te_ix],
            "test_pred": [float(v) for v in pred],
        })

    min_sp = min(r["spearman"] for r in seed_rows)
    return {
        "feature_columns": int(X.shape[1]),
        "n_rows": int(n),
        "n_seeds": int(n_seeds),
        "threshold": threshold,
        "test_fraction": float(frac),
        "all_pass": bool(min_sp >= threshold),
        "min_spearman": min_sp,
        "seeds": seed_rows,
    }


def main(argv: Optional[list] = None) -> int:
    ap = argparse.ArgumentParser(
        description="Wafer-yield rank-accuracy gate trainer.")
    ap.add_argument("--features", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--n_seeds", type=int, default=10)
    ap.add_argument("--threshold", type=float, default=0.92)
    ap.add_argument("--test_fraction", type=float, default=0.2)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    try:
        X = np.load(args.features)
        y = np.load(args.target)
    except Exception as exc:
        print("error: cannot load inputs: %s" % exc, file=sys.stderr)
        return 1
    if X.ndim != 2 or y.ndim != 1:
        print("error: expected 2-D features and 1-D target", file=sys.stderr)
        return 1

    try:
        report = run_pipeline(X, y, n_seeds=args.n_seeds,
                              threshold=args.threshold)
    except Exception as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$PROGRAM"

# Run the produced program on the visible fixtures to generate the deliverable.
python3 "$PROGRAM" \
    --features /app/wafer_features.npy \
    --target /app/wafer_yield.npy \
    --n_seeds 10 \
    --threshold 0.92 \
    --out "$REPORT"

echo "solve.sh done -> $PROGRAM and $REPORT"
ls -l "$PROGRAM" "$REPORT"
