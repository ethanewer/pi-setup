#!/bin/bash
# Oracle for fennel-row: write the generic config-driven trainer, then RUN it
# on the visible config to produce the experiment artifacts. Never reads /tests.
set -eu

TRAINER="/app/train.py"

cat > "$TRAINER" <<'PY'
#!/usr/bin/env python3
"""Config-driven deterministic logistic-regression trainer.

Every run writes its artifacts under paths.experiment:
  <experiment>/config.json   (effective config copy)
  <experiment>/progress.json (per-epoch losses)
and the fitted model to paths.model.
"""
import argparse
import csv
import json
import math
import os


def load_config(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_dataset(csv_path, features, target):
    xs, ys = [], []
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            xs.append([float(row[f]) for f in features])
            ys.append(float(row[target]))
    return xs, ys


def standardize(xs):
    n = len(xs)
    d = len(xs[0])
    means = [sum(x[j] for x in xs) / n for j in range(d)]
    stds = []
    for j in range(d):
        var = sum((x[j] - means[j]) ** 2 for x in xs) / n
        stds.append(math.sqrt(var) or 1.0)
    zs = [[(x[j] - means[j]) / stds[j] for j in range(d)] for x in xs]
    return zs, means, stds


def train(xs, ys, epochs, lr, seed):
    # Deterministic zero init (seed kept for contract completeness).
    d = len(xs[0])
    w = [0.0] * d
    b = 0.0
    n = len(xs)
    losses = []
    for _ in range(epochs):
        gw = [0.0] * d
        gb = 0.0
        loss = 0.0
        for x, y in zip(xs, ys):
            z = b + sum(wi * xi for wi, xi in zip(w, x))
            p = 1.0 / (1.0 + math.exp(-max(min(z, 500.0), -500.0)))
            p = min(max(p, 1e-12), 1.0 - 1e-12)
            loss += -(y * math.log(p) + (1 - y) * math.log(1 - p))
            err = p - y
            for j in range(d):
                gw[j] += err * x[j]
            gb += err
        losses.append(loss / n)
        for j in range(d):
            w[j] -= lr * gw[j] / n
        b -= lr * gb / n
    return w, b, losses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/app/config.json")
    args = ap.parse_args()

    cfg = load_config(args.config)
    features = cfg["data"]["features"]
    target = cfg["data"]["target"]
    epochs = int(cfg["training"]["epochs"])
    lr = float(cfg["training"]["learning_rate"])
    seed = int(cfg["training"]["seed"])

    xs, ys = load_dataset(cfg["paths"]["dataset"], features, target)
    zs, means, stds = standardize(xs)
    w, b, losses = train(zs, ys, epochs, lr, seed)

    exp_dir = cfg["paths"]["experiment"]
    os.makedirs(exp_dir, exist_ok=True)
    with open(os.path.join(exp_dir, "config.json"), "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
    with open(os.path.join(exp_dir, "progress.json"), "w", encoding="utf-8") as fh:
        json.dump(losses, fh)

    model = {
        "features": features,
        "target": target,
        "epochs": epochs,
        "weights": w,
        "bias": b,
        "standardization": {"means": means, "stds": stds},
    }
    with open(cfg["paths"]["model"], "w", encoding="utf-8") as fh:
        json.dump(model, fh, indent=2)


if __name__ == "__main__":
    main()
PY
chmod +x "$TRAINER"

python3 "$TRAINER" --config /app/config.json

echo "solve.sh done"
ls -l "$TRAINER" /app/model.json /app/experiments/frost-29/seed-5/
