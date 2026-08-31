#!/bin/bash
# Oracle for coral-basin: write the streaming bag scorer (this IS the work),
# then RUN it on the visible bag file to produce /app/bag_means.txt.
# Never reads /tests.
set -eu

SCORER="/app/bag_mean.py"
OUT="/app/bag_means.txt"

cat > "$SCORER" <<'PY'
"""Streaming per-bag mean of P(class=1) under the frozen triage model.

Usage:  python3 /app/bag_mean.py <bag.csv> <out.txt>
"""
import sys

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as NF

F, HID, C = 20, 32, 2
FEATS = ["x%d" % i for i in range(F)]
MODEL = "/app/triage_model.pt"
CHUNK = 8192


def fail(msg):
    print("bag_mean.py error: %s" % msg, file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) != 3:
        fail("usage: python3 bag_mean.py <bag.csv> <out.txt>")
    bag_path, out_path = sys.argv[1], sys.argv[2]

    try:
        sd = torch.load(MODEL, map_location="cpu")
    except Exception as e:
        fail("cannot load frozen model: %r" % (e,))
    model = nn.Sequential(nn.Linear(F, HID), nn.ReLU(), nn.Linear(HID, C))
    model.load_state_dict(sd)
    model.eval()

    sums, counts, order = {}, {}, []
    try:
        for chunk in pd.read_csv(bag_path, chunksize=CHUNK):
            missing = [c for c in ["bag_id"] + FEATS if c not in chunk.columns]
            if missing:
                fail("bag file missing required columns: %s" % missing)
            if len(chunk) == 0:
                continue
            X = torch.from_numpy(chunk[FEATS].to_numpy(dtype=np.float32))
            with torch.no_grad():
                p1 = NF.softmax(model(X), dim=1)[:, 1].double().tolist()
            for b, v in zip(chunk["bag_id"].to_numpy(), p1):
                b = int(b)
                if b not in sums:
                    sums[b] = 0.0
                    counts[b] = 0
                    order.append(b)
                sums[b] += v
                counts[b] += 1
    except SystemExit:
        raise
    except Exception as e:
        fail("cannot process bag file: %r" % (e,))

    lines = ["%.4f" % (sums[b] / counts[b]) for b in order]
    text = "".join(l + "\n" for l in lines)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(text)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
PY

chmod +x "$SCORER"

# Run the produced scorer on the visible bag to create the second deliverable.
python3 "$SCORER" /app/data/sensor_bags.csv "$OUT"

echo "solve.sh done -> $SCORER and $OUT"
ls -l "$SCORER" "$OUT"
