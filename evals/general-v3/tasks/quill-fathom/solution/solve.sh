#!/bin/bash
# Oracle for quill-fathom: write the reusable fine-tuning script (this IS the
# work), then RUN it on the visible press fold to produce /app/adapted_press.pt.
# Never reads /tests.
set -eu

ADAPT="/app/adapt.py"
OUT="/app/adapted_press.pt"

cat > "$ADAPT" <<'PY'
"""Reusable per-press fine-tuning script.

Usage:  python3 /app/adapt.py <fold.csv> <out_snapshot.pt>

Loads the frozen base checkpoint from /app/base_snapshot.pt, fine-tunes it on
the given press fold for a capped number of CPU epochs, and writes the adapted
state_dict to <out_snapshot.pt>.
"""
import os
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

F, HID, C = 16, 24, 3
FEATS = ["x%d" % i for i in range(F)]
BASE = "/app/base_snapshot.pt"
EPOCHS, LR, BATCH, SEED = 12, 0.1, 64, 7


def fail(msg):
    print("adapt.py error: %s" % msg, file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) != 3:
        fail("usage: python3 adapt.py <fold.csv> <out_snapshot.pt>")
    fold_path, out_path = sys.argv[1], sys.argv[2]

    try:
        df = pd.read_csv(fold_path)
    except Exception as e:
        fail("cannot read fold: %r" % (e,))
    missing = [c for c in FEATS + ["label"] if c not in df.columns]
    if missing:
        fail("fold missing required columns: %s" % missing)
    if len(df) == 0:
        fail("fold has zero data rows")
    if not os.path.isfile(BASE):
        fail("base checkpoint missing at %s" % BASE)

    torch.manual_seed(SEED)
    np.random.seed(SEED)
    net = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
    net.load_state_dict(torch.load(BASE, map_location="cpu"))

    X = torch.from_numpy(df[FEATS].to_numpy(dtype=np.float32))
    y = torch.from_numpy(df["label"].to_numpy(dtype=np.int64))

    opt = torch.optim.SGD(net.parameters(), lr=LR, momentum=0.9)
    net.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(len(X))
        for i in range(0, len(X), BATCH):
            idx = perm[i:i + BATCH]
            loss = NF.cross_entropy(net(X[idx]), y[idx])
            opt.zero_grad()
            loss.backward()
            opt.step()

    net.eval()
    with torch.no_grad():
        acc = (net(X).argmax(1) == y).float().mean().item()
    torch.save(net.state_dict(), out_path)
    print("finetune_accuracy=%.4f" % acc)


if __name__ == "__main__":
    main()
PY

chmod +x "$ADAPT"

# Run the produced script on the visible fold to create the second deliverable.
python3 "$ADAPT" /app/data/press_fold.csv "$OUT"

echo "solve.sh done -> $ADAPT and $OUT"
ls -l "$ADAPT" "$OUT"
