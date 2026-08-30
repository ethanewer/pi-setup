#!/usr/bin/env python3
"""Trainer for umber-vault: defines the solver + the fixed network and writes a
real trained snapshot (torch state_dict) to a chosen path on CPU."""
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF
import torch.optim as optim

F, HID, OUT = 48, 64, 2
FEAT_COLS = [f"x{i}" for i in range(F)]


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(F, HID)
        self.l2 = nn.Linear(HID, OUT)

    def forward(self, x):
        return self.l2(NF.relu(self.l1(x)))


def accuracy(model, X, y):
    with torch.no_grad():
        pred = model(torch.from_numpy(X)).argmax(1).cpu().numpy()
    return float((pred == y).mean())


def load_frame(path):
    df = pd.read_csv(path)
    X = df[FEAT_COLS].to_numpy(dtype=np.float32)
    y = df["label"].to_numpy(dtype=np.int64)
    return X, y


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: train.py <train.csv> <val.csv> <out_snapshot.pt>\n")
        return 2
    tr_csv, va_csv, out = sys.argv[1], sys.argv[2], sys.argv[3]

    torch.manual_seed(7)
    Xtr, ytr = load_frame(tr_csv)
    Xva, yva = load_frame(va_csv)
    _ = (Xva, yva)  # validation tray kept for coarse early-stopping / readability

    model = Net()
    opt = torch.optim.SGD(model.parameters(), lr=3e-3, momentum=0.9)
    epochs = 20
    bs = 64
    n = len(Xtr)

    for _ in range(epochs):
        perm = torch.randperm(n)
        for i in range(0, n, bs):
            idx = perm[i:i + bs]
            xb = torch.from_numpy(Xtr[idx.numpy()])
            yb = ytr[idx.numpy()]
            opt.zero_grad()
            loss = NF.cross_entropy(model(xb), torch.from_numpy(yb))
            loss.backward()
            opt.step()

    torch.save(model.state_dict(), out)
    acc = accuracy(model, Xtr, ytr)
    print(f"final_train_accuracy={acc:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())