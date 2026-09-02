#!/usr/bin/env python3
"""Predict CLI + streaming large-bag scorer for umber-vault.

  predict.py <features.csv> <out_labels.txt>   -- one digit per row
  predict.py --bag <bag.csv> <out_scores.txt>  -- one majority digit per bag

Reads input solely through the line-streaming csv module and processes rows in
bounded batches, so arbitrarily large bags stay memory-flat and scale linearly.
The same digits are emitted to stdout and written to the result file.
"""
import csv
import sys

import numpy as np
import torch

# Keep CPU overhead bounded: a single thread avoids per-thread OpenMP buffers.
torch.set_num_threads(1)
torch.set_num_interop_threads(1)

F, HID, OUT = 48, 64, 2
FEAT_COLS = [f"x{i}" for i in range(F)]
BASE = "/app/model_snapshot.pt"
CHUNK = 2048


class Net(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.l1 = torch.nn.Linear(F, HID)
        self.l2 = torch.nn.Linear(HID, OUT)

    def forward(self, x):
        return self.l2(torch.relu(self.l1(x)))


def load_net():
    net = Net()
    net.load_state_dict(torch.load(BASE, map_location="cpu"))
    net.eval()
    return net


def emit(lines, out_path):
    text = "".join(f"{int(v)}\n" for v in lines)
    with open(out_path, "w") as fh:
        fh.write(text)
    sys.stdout.write(text)


def main():
    argv = list(sys.argv[1:])
    if argv and argv[0] == "--bag":
        if len(argv) != 3:
            sys.stderr.write("usage: predict.py --bag <bag.csv> <out.txt>\n")
            return 2
        return bag_mode(argv[1], argv[2])
    if len(argv) != 2:
        sys.stderr.write("usage: predict.py <features.csv> <out_labels.txt>\n")
        return 2
    return rows_mode(argv[0], argv[1])


def rows_mode(path, out_path):
    net = load_net()
    labels = []
    with open(path, newline="") as fh:
        rd = csv.reader(fh)
        try:
            header = next(rd)
        except StopIteration:
            header = []
        col = {c: i for i, c in enumerate(header)}
        missing = [c for c in FEAT_COLS if c not in col]
        if missing:
            raise ValueError("missing feature columns")
        buf = []
        for row in rd:
            if not row:
                continue
            buf.append([float(row[col[c]]) for c in FEAT_COLS])
            if len(buf) >= CHUNK:
                labels.extend(_predict(net, buf))
                buf = []
        if buf:
            labels.extend(_predict(net, buf))
    emit(labels, out_path)
    return 0


def bag_mode(path, out_path):
    net = load_net()
    tally = {}
    order = []
    with open(path, newline="") as fh:
        rd = csv.reader(fh)
        try:
            header = next(rd)
        except StopIteration:
            header = []
        col = {c: i for i, c in enumerate(header)}
        missing = [c for c in FEAT_COLS if c not in col]
        if missing or "bag_id" not in col:
            raise ValueError("missing feature/bag columns")
        bidx = col["bag_id"]
        pairs = []
        for row in rd:
            if not row:
                continue
            b = int(float(row[bidx]))
            pairs.append((b, [float(row[col[c]]) for c in FEAT_COLS]))
            if len(pairs) >= CHUNK:
                _apply_batch(net, pairs, tally, order)
                pairs = []
        if pairs:
            _apply_batch(net, pairs, tally, order)
    lines = []
    for b in order:
        c = tally[b]
        lines.append(1 if c[1] > c[0] else 0)
    emit(lines, out_path)
    return 0


def _predict(net, rows):
    X = np.asarray(rows, dtype=np.float32)
    with torch.no_grad():
        return net(torch.from_numpy(X)).argmax(1).cpu().tolist()


def _apply_batch(net, pairs, tally, order):
    X = np.asarray([p[1] for p in pairs], dtype=np.float32)
    with torch.no_grad():
        lab = net(torch.from_numpy(X)).argmax(1).cpu().numpy()
    for (b, _), l in zip(pairs, lab):
        cnt = tally.get(b)
        if cnt is None:
            tally[b] = [0, 0]
            order.append(b)
            cnt = tally[b]
        cnt[int(l)] += 1


if __name__ == "__main__":
    sys.exit(main())