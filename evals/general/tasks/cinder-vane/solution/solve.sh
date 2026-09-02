#!/bin/bash
# Oracle for cinder-vane: author the Hydra-driven trainer + config group files,
# then RUN the default configuration on the visible fixture to produce
# /app/report.json and /app/model.json. Never reads /tests.
set -eu

mkdir -p /app/mode

# ---- 1. Root config -------------------------------------------------------
cat > /app/config.yaml <<'YAML'
defaults:
  - _self_
  - mode: standard
dataset: /app/data/readings.csv
learning_rate: 0.05
l2: 0.001
seed: 7
outputs:
  model: /app/model.json
  report: /app/report.json
YAML

# ---- 2. Mode group files --------------------------------------------------
cat > /app/mode/standard.yaml <<'YAML'
# @package _global_
epochs: 40
batch_size: 64
debug: false
YAML

cat > /app/mode/debug.yaml <<'YAML'
# @package _global_
epochs: 1
batch_size: 8
debug: true
outputs:
  model: /app/model_debug.json
  report: /app/report_debug.json
YAML

# ---- 3. The trainer (this IS the work) -------------------------------------
cat > /app/train.py <<'PY'
"""Hydra-driven logistic calibrator for Peakline lift telemetry."""
import json
import os
import sys

import numpy as np
from hydra import compose, initialize_config_dir


def sigmoid(z):
    out = np.empty_like(z)
    pos = z >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-z[pos]))
    ez = np.exp(z[~pos])
    out[~pos] = ez / (1.0 + ez)
    return out


def load_csv(path):
    with open(path, "r", encoding="utf-8") as fh:
        header = fh.readline().strip().split(",")
    if header != ["vibration", "hours_since_service", "load", "needs_recal"]:
        raise SystemExit("unexpected CSV header: %r" % (header,))
    X, y = [], []
    with open(path, "r", encoding="utf-8") as fh:
        next(fh)
        for line in fh:
            line = line.strip()
            if not line:
                continue
            a, b, c, t = line.split(",")
            X.append([float(a), float(b), float(c)])
            y.append(float(t))
    return np.asarray(X, dtype=float), np.asarray(y, dtype=float)


def main():
    overrides = [o for o in sys.argv[1:] if o.strip()]
    cfg_dir = os.path.dirname(os.path.abspath(__file__))
    with initialize_config_dir(config_dir=cfg_dir, version_base=None):
        cfg = compose(config_name="config", overrides=overrides)

    X, y = load_csv(cfg.dataset)
    n, d = X.shape
    lr = float(cfg.learning_rate)
    l2 = float(cfg.l2)
    seed = int(cfg.seed)
    epochs = int(cfg.epochs)
    batch = int(cfg.batch_size)

    w = np.zeros(d)
    bias = 0.0
    rng = np.random.default_rng(seed)
    for _ in range(epochs):
        perm = rng.permutation(n)
        for start in range(0, n, batch):
            idx = perm[start:start + batch]
            xb, yb = X[idx], y[idx]
            z = xb @ w + bias
            p = sigmoid(z)
            err = p - yb
            gw = xb.T @ err / len(idx) + l2 * w
            gb = float(err.mean())
            w -= lr * gw
            bias -= lr * gb

    probs = sigmoid(X @ w + bias)
    preds = (probs > 0.5).astype(float)
    accuracy = float((preds == y).mean())
    eps = 1e-12
    final_loss = float(-np.mean(y * np.log(probs + eps)
                                + (1 - y) * np.log(1 - probs + eps)))

    os.makedirs(os.path.dirname(os.path.abspath(cfg.outputs.model)), exist_ok=True)
    with open(cfg.outputs.model, "w", encoding="utf-8") as fh:
        json.dump({"weights": [float(v) for v in w],
                   "bias": float(bias), "n_features": int(d)}, fh, indent=2)

    report = {
        "debug": bool(cfg.debug),
        "epochs_effective": epochs,
        "batch_size": batch,
        "learning_rate": lr,
        "l2": l2,
        "seed": seed,
        "dataset": str(cfg.dataset),
        "n_rows": int(n),
        "n_features": int(d),
        "accuracy": accuracy,
        "final_loss": final_loss,
    }
    os.makedirs(os.path.dirname(os.path.abspath(cfg.outputs.report)), exist_ok=True)
    with open(cfg.outputs.report, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)

    print("TRAIN_OK accuracy=%.4f debug=%s epochs=%d" % (accuracy, cfg.debug, epochs))


if __name__ == "__main__":
    main()
PY

chmod +x /app/train.py

# ---- 4. Produce the visible-case deliverables by actually running ----------
python3 /app/train.py
python3 /app/train.py mode=debug

echo "solve.sh done -> trainer + config + reports + models"
ls -l /app/train.py /app/config.yaml /app/mode /app/report.json /app/model.json /app/report_debug.json /app/model_debug.json
