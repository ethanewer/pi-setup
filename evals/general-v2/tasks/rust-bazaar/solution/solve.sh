#!/bin/bash
# Oracle for rust-bazaar: write the reusable fine-tuning program, then RUN it
# on the visible fold to produce /app/ft_visible.pt. Never reads /tests.
set -eu

FINETUNER="/app/finetune.py"
OUT="/app/ft_visible.pt"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$FINETUNER" <<'PY'
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn

F, H, C = 24, 48, 3
FEATS = [f"x{i}" for i in range(F)]
BASE = "/app/base_snapshot.pt"
EPOCHS = 50  # capped: strictly fewer than 60


class Net(nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = nn.Linear(F, H)
        self.l2 = nn.Linear(H, C)

    def forward(self, x):
        return self.l2(torch.relu(self.l1(x)))


def remap(sd):
    """Accept any four-tensor 24->48->3 state_dict regardless of param names."""
    fresh = {}
    for k, v in sd.items():
        root = "l1" if tuple(v.shape) in ((H, F), (H,)) else "l2"
        suffix = ".weight" if k.endswith(".weight") else ".bias"
        fresh[root + suffix] = v.float()
    return fresh


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) != 3:
        fail("usage: finetune.py <fold.csv> <out_snapshot.pt>")
    fold_path, out_path = sys.argv[1], sys.argv[2]
    try:
        df = pd.read_csv(fold_path)
    except Exception as e:
        fail(f"unreadable fold: {e}")
    missing = [c for c in FEATS + ["label"] if c not in df.columns]
    if missing:
        fail(f"fold missing required columns: {missing}")
    if len(df) == 0:
        fail("fold has zero data rows; nothing to fine-tune on")
    X = df[FEATS].to_numpy(dtype=np.float32)
    if not np.isfinite(X).all():
        fail("fold contains non-finite feature values")
    y = torch.from_numpy(df["label"].to_numpy(dtype=np.int64))

    model = Net()
    model.load_state_dict(remap(torch.load(BASE, map_location="cpu")))
    torch.manual_seed(7)
    opt = torch.optim.Adam(model.parameters(), lr=3e-3)
    lossf = nn.CrossEntropyLoss()
    Xt = torch.from_numpy(X)
    n = len(Xt)
    g = torch.Generator().manual_seed(123)
    for _ in range(EPOCHS):
        model.train()
        perm = torch.randperm(n, generator=g)
        for i in range(0, n, 64):
            idx = perm[i:i + 64]
            opt.zero_grad()
            loss = lossf(model(Xt[idx]), y[idx])
            loss.backward()
            opt.step()
    model.eval()
    with torch.no_grad():
        acc = float((model(Xt).argmax(1) == y).float().mean())
    torch.save(model.state_dict(), out_path)
    print(f"finetune_accuracy={acc:.4f}")


if __name__ == "__main__":
    main()
PY

chmod +x "$FINETUNER"

# 2. Run the produced program on the visible fold to generate the artifact.
python3 "$FINETUNER" /app/data/line_fold.csv "$OUT"

echo "solve.sh done -> $FINETUNER and $OUT"
ls -l "$FINETUNER" "$OUT"
