#!/bin/bash
# Oracle for saffron-ember: write the reusable fine-tuning script, then RUN it
# on the shipped drifted fold to produce /app/finetuned.pt. Never reads /tests.
set -eu

FT="/app/finetune.py"

cat > "$FT" <<'PY'
"""Reusable fine-tuner: adapt the deployed buoy salinity model to a
drifted-regime calibration fold."""
import argparse
import csv
import sys

import torch
import torch.nn as nn

BASE = "/app/base_model.pt"
DIM, HID, CLS = 16, 24, 3


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def load_fold(path):
    """Return (X float32 (n,16), y int64 (n,)) or die on malformed input."""
    try:
        with open(path, newline="", encoding="utf-8") as fh:
            reader = csv.reader(fh)
            header = next(reader, None)
            if header is None:
                die("empty fold file")
            header = [h.strip() for h in header]
            if "label" not in header:
                die("fold has no 'label' column")
            if "id" not in header:
                die("fold has no 'id' column")
            feat_cols = [i for i, h in enumerate(header) if h.startswith("f")]
            if len(feat_cols) != DIM:
                die("expected %d feature columns f0..f15, found %d"
                    % (DIM, len(feat_cols)))
            label_col = header.index("label")
            X, y = [], []
            for row in reader:
                if not row or all(not c.strip() for c in row):
                    continue
                feats = []
                for i in feat_cols:
                    feats.append(float(row[i]))  # ValueError on non-numeric
                lab = int(row[label_col])
                if not (0 <= lab < CLS):
                    die("label %r out of range" % row[label_col])
                X.append(feats)
                y.append(lab)
    except ValueError as exc:
        die("non-numeric value in fold: %s" % exc)
    except OSError as exc:
        die("cannot read fold: %s" % exc)
    if not X:
        die("fold has zero data rows")
    return torch.tensor(X, dtype=torch.float32), torch.tensor(y, dtype=torch.int64)


def load_base():
    """Load the deployed snapshot, remapping arbitrary parameter names to the
    canonical layout by tensor shape."""
    try:
        sd = torch.load(BASE, map_location="cpu")
    except Exception as exc:
        die("cannot load base snapshot: %s" % exc)
    fresh = {}
    for k, v in sd.items():
        if tuple(v.shape) == (HID, DIM):
            fresh["l1.weight"] = v
        elif tuple(v.shape) == (HID,):
            fresh["l1.bias"] = v
        elif tuple(v.shape) == (CLS, HID):
            fresh["l2.weight"] = v
        elif tuple(v.shape) == (CLS,):
            fresh["l2.bias"] = v
        else:
            die("unexpected tensor %r with shape %s" % (k, tuple(v.shape)))
    for need in ("l1.weight", "l1.bias", "l2.weight", "l2.bias"):
        if need not in fresh:
            die("base snapshot missing %s" % need)
    return fresh


def build_model(sd):
    m = nn.Sequential(nn.Linear(DIM, HID), nn.ReLU(), nn.Linear(HID, CLS))
    seq_sd = {}
    for k, v in sd.items():
        if k.startswith("l1."):
            seq_sd["0." + k.split(".", 1)[1]] = v
        elif k.startswith("l2."):
            seq_sd["2." + k.split(".", 1)[1]] = v
        else:
            seq_sd[k] = v
    m.load_state_dict(seq_sd)
    return m


def finetune(fold_csv, out_pt, epochs=20):
    if epochs > 30:
        die("--epochs is capped at 30")
    if epochs < 1:
        die("--epochs must be >= 1")
    X, y = load_fold(fold_csv)
    base_sd = load_base()
    model = build_model(base_sd)
    model.train()
    torch.manual_seed(11)
    opt = torch.optim.SGD(model.parameters(), lr=0.05, momentum=0.9)
    lossf = nn.CrossEntropyLoss()
    n = X.shape[0]
    g = torch.Generator().manual_seed(5)
    for _ in range(epochs):
        perm = torch.randperm(n, generator=g)
        for lo in range(0, n, 64):
            sel = perm[lo:lo + 64]
            opt.zero_grad()
            loss = lossf(model(X[sel]), y[sel])
            loss.backward()
            opt.step()
    model.eval()
    with torch.no_grad():
        acc = float((model(X).argmax(1) == y).float().mean())
    out_sd = {
        "l1.weight": model[0].weight.detach().clone(),
        "l1.bias": model[0].bias.detach().clone(),
        "l2.weight": model[2].weight.detach().clone(),
        "l2.bias": model[2].bias.detach().clone(),
    }
    torch.save(out_sd, out_pt)
    print("finetune_accuracy=%.4f" % acc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fold_csv")
    ap.add_argument("out_snapshot")
    ap.add_argument("--epochs", type=int, default=20)
    args = ap.parse_args()
    finetune(args.fold_csv, args.out_snapshot, args.epochs)


if __name__ == "__main__":
    main()
PY

chmod +x "$FT"

python3 "$FT" /app/data/fold_a.csv /app/finetuned.pt

echo "solve.sh done"
ls -l "$FT" /app/finetuned.pt
