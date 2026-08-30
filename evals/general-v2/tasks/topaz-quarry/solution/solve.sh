#!/bin/bash
# Oracle for topaz-quarry: author the trainer per the contract, then RUN it on
# the visible fixtures to produce /app/model.pt. Never reads /tests.
set -eu

cat > /app/train.py <<'PY'
import csv
import json
import sys

import torch
import torch.nn as nn


class Net(nn.Module):
    def __init__(self, input_dim, classes):
        super().__init__()
        self.fc = nn.Linear(input_dim, classes)

    def forward(self, x):
        return self.fc(x)


def load_csv(path, input_dim):
    feats, labels = [], []
    with open(path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        cols = ["f%d" % j for j in range(input_dim)]
        has_label = "label" in reader.fieldnames
        for row in reader:
            feats.append([float(row[c]) for c in cols])
            if has_label:
                labels.append(int(row["label"]))
    return torch.tensor(feats, dtype=torch.float32), torch.tensor(labels)


def main():
    train_csv, config_json, out_pt = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(config_json, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)
    D, C = int(cfg["input_dim"]), int(cfg["classes"])
    max_epochs = int(cfg.get("max_epochs", 40))

    torch.manual_seed(0)
    model = Net(D, C)
    X, y = load_csv(train_csv, D)

    # Train directly on the raw feature values so the saved snapshot predicts
    # raw inputs (the deployment verifier feeds raw eval rows).
    opt = torch.optim.SGD(model.parameters(), lr=0.1, momentum=0.9)
    for _ in range(max_epochs):
        opt.zero_grad()
        loss = nn.functional.cross_entropy(model(X), y)
        loss.backward()
        opt.step()

    with open(out_pt, "wb") as fh:
        torch.save(model.state_dict(), fh)
    print("saved snapshot to %s" % out_pt)


if __name__ == "__main__":
    main()
PY

chmod +x /app/train.py

python3 /app/train.py /app/data/train.csv /app/data/config.json /app/model.pt

echo "solve.sh done"
ls -l /app/train.py /app/model.pt
