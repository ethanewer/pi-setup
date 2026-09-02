#!/usr/bin/env python3
"""Fixture generator for juniper-gasket: greenhouse contamination screening.

Generates a visible case and hidden cases: each is a directory with
train.csv, test.csv and meta.json. The two classes are Gaussian blobs in
6 numeric sensor features with a class-dependent covariance tilt, so a
plain logistic regression comfortably clears the stated accuracy floor.

Usage: python3 gen.py <outdir> <case_id> <seed> [n_train] [n_test] [sep]
"""
import csv
import json
import os
import sys

import numpy as np

FEATURES = ["moisture", "weight_kg", "metal_signal", "odor_score",
            "optical_density", "conductivity"]


def main():
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    n_train = int(sys.argv[4]) if len(sys.argv) > 4 else 1200
    n_test = int(sys.argv[5]) if len(sys.argv) > 5 else 500
    sep = float(sys.argv[6]) if len(sys.argv) > 6 else 2.2
    floor = 0.85

    g = np.random.default_rng(seed)
    d = len(FEATURES)

    # class-conditional means: clean ~ 0, contaminated ~ sep * direction
    direction = g.normal(0.0, 1.0, (d,))
    direction = direction / np.linalg.norm(direction)
    mean1 = sep * direction
    # mild per-feature scale differences
    scale = g.uniform(0.8, 1.4, (d,))

    def sample(n):
        y = (g.random(n) < 0.5).astype(np.int64)
        X = np.empty((n, d), np.float64)
        m0 = g.normal(0.0, 0.6, (d,))  # clean-cluster wobble
        for i in range(n):
            mu = m0 if y[i] == 0 else mean1 + m0 * 0.3
            X[i] = mu + g.normal(0.0, 1.0, (d,)) * scale
        # measurement noise floor
        X += g.normal(0.0, 0.15, X.shape)
        return X, y

    Xtr, ytr = sample(n_train)
    Xte, yte = sample(n_test)

    def write_csv(path, X, y):
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(FEATURES + ["contaminated"])
            for row, lab in zip(X, y):
                w.writerow(["%.4f" % v for v in row] + [int(lab)])

    os.makedirs(outdir, exist_ok=True)
    write_csv(os.path.join(outdir, "train.csv"), Xtr, ytr)
    write_csv(os.path.join(outdir, "test.csv"), Xte, yte)
    meta = {
        "case_id": case_id,
        "seed": seed,
        "features": FEATURES,
        "target": "contaminated",
        "classes": [0, 1],
        "accuracy_floor": floor,
        "n_train": n_train,
        "n_test": n_test,
    }
    with open(os.path.join(outdir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print("%s: pos-rate train=%.3f test=%.3f" % (case_id, ytr.mean(),
                                                 yte.mean()))


if __name__ == "__main__":
    main()
