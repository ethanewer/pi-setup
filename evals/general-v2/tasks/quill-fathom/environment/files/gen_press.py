"""Build-time fixture generator for quill-fathom.

Produces, at image build time and from fixed seeds only:
  /app/data/base_train.csv        -- labeled rows the base snapshot was trained on
  /app/data/press_fold.csv        -- the visible press fold the agent fine-tunes on
  /app/base_snapshot.pt           -- frozen base checkpoint (Linear 16->24, ReLU, 24->3)

The concrete per-fold class rules live only here; the generator is removed from
the image after generation so the agent must genuinely fine-tune rather than
reconstruct the rules.
"""
import os

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

F, HID, C = 16, 24, 3
FEATS = [f"x{i}" for i in range(F)]
DATA = "/app/data"
os.makedirs(DATA, exist_ok=True)

BASE_W = np.array([2.5, -1.8, 1.2] + [0.0] * (F - 3))


def make_rows(rng, n, w, lo, hi, margin=0.35, span=1.5):
    """n rows whose class is far enough from both thresholds to be unambiguous."""
    feats, labs = [], []
    while len(labs) < n:
        rows = rng.uniform(-span, span, (n * 2, F))
        s = rows @ w
        lab = np.where(s < lo, 0, np.where(s < hi, 1, 2))
        ok = (np.abs(s - lo) > margin) & (np.abs(s - hi) > margin)
        feats.append(rows[ok])
        labs.append(lab[ok])
    return np.concatenate(feats)[:n], np.concatenate(labs)[:n].astype(np.int64)


def frame(feats, labs, start_id):
    df = pd.DataFrame(feats, columns=FEATS)
    df.insert(0, "id", np.arange(start_id, start_id + len(feats), dtype=np.int64))
    df["label"] = labs
    return df.round(6)


def train_base(feats, labs, seed=4100, epochs=60, lr=0.1, batch=128):
    torch.manual_seed(seed)
    net = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
    opt = torch.optim.SGD(net.parameters(), lr=lr, momentum=0.9)
    X = torch.from_numpy(feats.astype(np.float32))
    y = torch.from_numpy(labs.astype(np.int64))
    for _ in range(epochs):
        perm = torch.randperm(len(X))
        for i in range(0, len(X), batch):
            idx = perm[i:i + batch]
            loss = NF.cross_entropy(net(X[idx]), y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()
    net.eval()
    with torch.no_grad():
        acc = (net(X).argmax(1) == y).float().mean().item()
    return net, acc


def main():
    # 1) base training set + frozen base checkpoint on the BASE rule.
    rng = np.random.default_rng(4101)
    feats, labs = make_rows(rng, 1500, BASE_W, -1.0, 1.0)
    frame(feats, labs, 0).to_csv(os.path.join(DATA, "base_train.csv"), index=False)
    net, acc = train_base(feats, labs)
    torch.save(net.state_dict(), "/app/base_snapshot.pt")
    print("base train accuracy:", round(acc, 4))

    # 2) visible press fold: same hyperplane, both thresholds shifted so the
    #    frozen base checkpoint alone stays below the 0.90 pass bar.
    rng = np.random.default_rng(4102)
    feats, labs = make_rows(rng, 600, BASE_W, -0.25, 1.75)
    frame(feats, labs, 9000).to_csv(os.path.join(DATA, "press_fold.csv"), index=False)


if __name__ == "__main__":
    main()
