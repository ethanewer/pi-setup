#!/bin/bash
# Oracle for moss-loft: authors the config-driven trainer deliverable, then
# RUNS it on the visible fixtures to produce /app/model_snapshot.pt. Never
# reads /tests.
set -eu

TRAINER="/app/train.py"
SNAPSHOT="/app/model_snapshot.pt"

cat > "$TRAINER" <<'PY'
#!/usr/bin/env python3
"""Config-driven snapshot trainer (moss-loft).

Trains Linear(d->h) ReLU Linear(h->h) ReLU Linear(h->classes) on a labeled
CSV for the configured number of epochs and saves the trained state dict.
"""
import csv
import json
import sys

import torch
import torch.nn as nn


def load_labeled_csv(path, input_dim):
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for rec in reader:
            feats = [float(rec["x%d" % j]) for j in range(input_dim)]
            rows.append((feats, int(rec["label"])))
    return rows


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: train.py <train_csv> <config_json> <output_pt>",
              file=sys.stderr)
        return 2
    train_csv, config_json, out_pt = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(config_json, encoding="utf-8") as fh:
        cfg = json.load(fh)
    input_dim = int(cfg["input_dim"])
    hidden = int(cfg["hidden_units"])
    classes = int(cfg["num_classes"])
    epochs = int(cfg["epochs"])
    lr = float(cfg["learning_rate"])
    batch = int(cfg["batch_size"])
    seed = int(cfg["seed"])

    torch.manual_seed(seed)
    data = load_labeled_csv(train_csv, input_dim)
    xs = torch.tensor([f for f, _ in data], dtype=torch.float32)
    ys = torch.tensor([y for _, y in data], dtype=torch.long)

    model = nn.Sequential(
        nn.Linear(input_dim, hidden), nn.ReLU(),
        nn.Linear(hidden, hidden), nn.ReLU(),
        nn.Linear(hidden, classes),
    )
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.CrossEntropyLoss()

    n = xs.shape[0]
    model.train()
    for _ in range(epochs):
        perm = torch.randperm(n)
        for start in range(0, n, batch):
            idx = perm[start:start + batch]
            opt.zero_grad()
            loss = loss_fn(model(xs[idx]), ys[idx])
            loss.backward()
            opt.step()

    model.eval()
    with torch.no_grad():
        acc = float((model(xs).argmax(dim=1) == ys).float().mean())
    torch.save(model.state_dict(), out_pt)
    print("trained: epochs=%d train_acc=%.4f -> %s" % (epochs, acc, out_pt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$TRAINER"

# Run the real work on the visible fixtures.
python3 "$TRAINER" /app/data/train.csv /app/config.json "$SNAPSHOT"

echo "solve.sh done -> $TRAINER and $SNAPSHOT"
ls -l "$TRAINER" "$SNAPSHOT"
