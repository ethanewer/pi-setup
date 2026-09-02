"""Build-time fixture generator for saffron-ember.

Creates:
  /app/base_model.pt      deployed base model: Linear(16->24) ReLU Linear(24->3),
                          trained on LAST season's water-mass layout.
  /app/data/fold_a.csv    a drifted-regime calibration fold (400 rows).

The drift rule: each water-mass class k is a spherical Gaussian in 16-D
centered on a fixed "signature" pattern (two active dimensions at +/-2.2).
The base model was trained on the OLD signature layout; this season's folds
use DRIFTED layouts (different active dimensions/signs). The rule constants
are shared with the verifier's hidden-fold generator.
Deterministic: fixed seeds everywhere.
"""
import os

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

DIM = 16
HID = 24
CLS = 3
SIG = 2.2

# signature layouts: class index -> {dim: value}
OLD_LAYOUT = [{0: SIG, 1: SIG}, {4: SIG, 5: SIG}, {8: SIG, 9: SIG}]
DRIFT_A = [{6: SIG, 7: SIG}, {10: SIG, 11: SIG}, {2: SIG, 3: SIG}]


def centers(layout):
    C = np.zeros((CLS, DIM))
    for k, sig in enumerate(layout):
        for d, v in sig.items():
            C[k, d] = v
    return C


def make_fold(layout, n, seed):
    rng = np.random.default_rng(seed)
    C = centers(layout)
    y = rng.integers(0, CLS, size=n)
    X = C[y] + rng.standard_normal((n, DIM))
    labels = np.array([int(np.argmin(((X[i] - C) ** 2).sum(1))) for i in range(n)])
    df = pd.DataFrame(X, columns=[f"f{d}" for d in range(DIM)])
    df.insert(0, "id", np.arange(1, n + 1))
    df["label"] = labels
    return df


def train_base():
    torch.manual_seed(20260830)
    # last season's samples under the OLD layout
    df = make_fold(OLD_LAYOUT, 1200, seed=7001)
    X = torch.tensor(df[[f"f{d}" for d in range(DIM)]].to_numpy(np.float32))
    y = torch.tensor(df["label"].to_numpy(np.int64))

    model = nn.Sequential(nn.Linear(DIM, HID), nn.ReLU(), nn.Linear(HID, CLS))
    opt = torch.optim.SGD(model.parameters(), lr=0.08, momentum=0.9)
    lossf = nn.CrossEntropyLoss()
    for epoch in range(400):
        opt.zero_grad()
        loss = lossf(model(X), y)
        loss.backward()
        opt.step()
    with torch.no_grad():
        acc = float((model(X).argmax(1) == y).float().mean())
    assert acc >= 0.93, "base model under-trained: acc=%.3f" % acc
    torch.save(model.state_dict(), "/app/base_model.pt")
    print("base trained, old-regime train acc=%.4f" % acc)


def main():
    os.makedirs("/app/data", exist_ok=True)
    train_base()
    fold = make_fold(DRIFT_A, n=400, seed=20260)
    fold.to_csv("/app/data/fold_a.csv", index=False)
    print("fold_a.csv written: %d rows" % len(fold))


if __name__ == "__main__":
    main()
