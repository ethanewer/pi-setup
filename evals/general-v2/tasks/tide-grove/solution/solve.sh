#!/bin/bash
# Oracle for tide-grove: authors /app/train.py, runs it on the visible data +
# config to produce the visible snapshot deliverable
# (/app/checkpoints/*/model.pt — here iter-120), then re-runs it once to prove
# determinism. Never reads /tests.
set -eu

# ---- 1. Author the trainer deliverable. ----
cat > /app/train.py <<'PY'
#!/usr/bin/env python3
"""tide-grove iteration-capped checkpoint trainer.

Usage: python3 /app/train.py <train_csv> <config_file> <ckpt_root>

Trains Linear(d, hidden) -> ReLU -> Linear(hidden, 2) full-batch with SGD
(momentum 0.9) for exactly `iterations` steps, then saves the state_dict to
<ckpt_root>/iter-<iterations>/model.pt plus a meta.json sidecar.
"""
import csv
import json
import os
import sys

import torch
import torch.nn as nn


def parse_config(path):
    cfg = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if "=" not in line:
                raise ValueError(f"bad config line: {raw!r}")
            key, _, value = line.partition("=")
            cfg[key.strip()] = value.strip()
    return {
        "iterations": int(cfg["iterations"]),
        "hidden": int(cfg["hidden"]),
        "lr": float(cfg["lr"]),
        "seed": int(cfg["seed"]),
    }


def read_csv(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        feature_idx = [i for i, name in enumerate(header) if name.startswith("x")]
        label_idx = header.index("label")
        xs, ys = [], []
        for row in reader:
            if not row:
                continue
            xs.append([float(row[i]) for i in feature_idx])
            ys.append(int(row[label_idx]))
    return torch.tensor(xs, dtype=torch.float32), torch.tensor(ys, dtype=torch.long), len(feature_idx)


def main():
    train_csv, config_path, ckpt_root = sys.argv[1], sys.argv[2], sys.argv[3]
    cfg = parse_config(config_path)
    x, y, d = read_csv(train_csv)

    torch.manual_seed(cfg["seed"])
    torch.use_deterministic_algorithms(True)
    model = nn.Sequential(
        nn.Linear(d, cfg["hidden"]),
        nn.ReLU(),
        nn.Linear(cfg["hidden"], 2),
    )
    opt = torch.optim.SGD(model.parameters(), lr=cfg["lr"], momentum=0.9)
    loss_fn = nn.CrossEntropyLoss()

    model.train()
    for _ in range(cfg["iterations"]):
        opt.zero_grad()
        loss = loss_fn(model(x), y)
        loss.backward()
        opt.step()
    model.eval()

    with torch.no_grad():
        acc = (model(x).argmax(dim=1) == y).float().mean().item()

    node = os.path.join(ckpt_root, f"iter-{cfg['iterations']}")
    os.makedirs(node, exist_ok=True)
    torch.save(model.state_dict(), os.path.join(node, "model.pt"))
    with open(os.path.join(node, "meta.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "iterations": cfg["iterations"],
            "hidden": cfg["hidden"],
            "lr": cfg["lr"],
            "seed": cfg["seed"],
            "feature_dim": d,
        }, fh, indent=2, sort_keys=True)

    print(f"final_accuracy={acc:.4f}")


if __name__ == "__main__":
    main()
PY
chmod +x /app/train.py

# ---- 2. Produce the visible snapshot deliverable. ----
python3 /app/train.py /app/data/train.csv /app/train_config.txt /app/checkpoints

# ---- 3. Determinism proof: re-run into a second root. ----
python3 /app/train.py /app/data/train.csv /app/train_config.txt /tmp/ckpt_rerun

echo "solve.sh done"
ls -l /app/train.py /app/checkpoints/iter-120/model.pt /tmp/ckpt_rerun/iter-120/model.pt
