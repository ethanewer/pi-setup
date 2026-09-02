#!/usr/bin/env python3
"""Reusable fine-tuner for umber-vault. Loads the base snapshot trained on the
source dataset and adapts it to a previously-unseen fold, saving a fresh
loadable state_dict that differs from the base."""
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

F, HID, OUT = 48, 64, 2
FEAT_COLS = [f"x{i}" for i in range(F)]
BASE = "/app/model_snapshot.pt"


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(F, HID)
        self.l2 = nn.Linear(HID, OUT)

    def forward(self, x):
        return self.l2(NF.relu(self.l1(x)))


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: finetune.py <fold.csv> <out_snapshot.pt>\n")
        return 2
    fold_csv, out = sys.argv[1], sys.argv[2]

    model = Net()
    model.load_state_dict(torch.load(BASE, map_location="cpu"))
    model.train()

    df = pd.read_csv(fold_csv)
    X = df[FEAT_COLS].to_numpy(dtype=np.float32)
    y = df["label"].to_numpy(dtype=np.int64)
    n = len(X)
    torch.manual_seed(11)
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    bs = 32
    epochs = 40
    for _ in range(epochs):
        perm = torch.randperm(n)
        for i in range(0, n, bs):
            idx = perm[i:i + bs]
            xb = torch.from_numpy(X[idx.numpy()])
            yb = torch.from_numpy(y[idx.numpy()])
            opt.zero_grad()
            loss = NF.cross_entropy(model(xb), yb)
            loss.backward()
            opt.step()

    torch.save(model.state_dict(), out)
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(X)).argmax(1).cpu().numpy()
    acc = float((pred == y).mean())
    print(f"finetune_accuracy={acc:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())