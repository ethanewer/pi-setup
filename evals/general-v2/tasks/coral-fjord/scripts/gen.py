#!/usr/bin/env python3
"""Fixture generator for coral-fjord: multi-stage sensor-fusion fixtures.

The label boundary lives ENTIRELY in a two-layer nonlinear "context" map:
    c_true = tanh(W2 @ tanh(W1 @ x) + b2);  y = 1 if w·c_true + b > 0 else 0
(with a few label flips). A model whose context stage is disconnected from
the optimizer cannot reproduce the boundary well; a model with full gradient
flow can fit it almost perfectly.

Usage: python3 gen.py <outdir> <case_id> <seed> [d_raw] [d_ctx] [n_train] [n_test]
"""
import json
import os
import sys

import numpy as np

def main():
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    d_raw = int(sys.argv[4]) if len(sys.argv) > 4 else 6
    d_ctx = int(sys.argv[5]) if len(sys.argv) > 5 else 16
    n_train = int(sys.argv[6]) if len(sys.argv) > 6 else 800
    n_test = int(sys.argv[7]) if len(sys.argv) > 7 else 300
    flip = 0.03

    g = np.random.default_rng(seed)
    X = g.normal(0.0, 1.0, (n_train + n_test, d_raw)).astype(np.float32)

    # teacher context map (fixed, seeded)
    W1 = g.normal(0.0, 1.0, (d_ctx, d_raw)) / np.sqrt(d_raw)
    b1 = g.normal(0.0, 0.3, (d_ctx,))
    W2 = g.normal(0.0, 1.0, (d_ctx, d_ctx)) / np.sqrt(d_ctx)
    b2 = g.normal(0.0, 0.3, (d_ctx,))
    w = g.normal(0.0, 1.0, (d_ctx,))
    w = w / np.linalg.norm(w)
    b = float(g.normal(0.0, 0.2))

    def label_of(Xa):
        h1 = np.tanh(Xa @ W1.T + b1)
        c = np.tanh(h1 @ W2.T + b2)
        z = c @ w + b
        return (z > 0).astype(np.int64)

    y = label_of(X)
    fl = g.random(len(y)) < flip
    y[fl] = 1 - y[fl]

    idx = g.permutation(len(y))
    X, y = X[idx], y[idx]
    Xtr, ytr = X[:n_train], y[:n_train]
    Xte, yte = X[n_train:], y[n_train:]

    # fixed gradient-probe batch (deterministic)
    cb_x = g.normal(0.0, 1.0, (32, d_raw)).astype(np.float32)
    cb_y = label_of(cb_x)

    meta = {
        "case_id": case_id,
        "seed": seed,
        "d_raw": d_raw,
        "d_ctx": d_ctx,
        "num_classes": 2,
        "train_epochs_hint": 900,
        "loss_target": 0.12,
        "accuracy_target": 0.90,
        "probe_seed": seed + 500,
    }
    os.makedirs(outdir, exist_ok=True)
    np.savez(os.path.join(outdir, "train.npz"), x=Xtr, y=ytr)
    np.savez(os.path.join(outdir, "test.npz"), x=Xte, y=yte)
    np.savez(os.path.join(outdir, "probe_batch.npz"), x=cb_x, y=cb_y)
    with open(os.path.join(outdir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    # linear-probe sanity: how well can a plain linear model do (lower bound)
    print("%s: pos-rate train=%.3f test=%.3f"
          % (case_id, ytr.mean(), yte.mean()))


if __name__ == "__main__":
    main()
