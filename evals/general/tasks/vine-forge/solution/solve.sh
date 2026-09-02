#!/bin/bash
# Oracle for vine-forge: write the streaming bag grader, then RUN it on the
# shipped bag to produce /app/event_scores.txt. Never reads /tests.
set -eu

SCORER="/app/scorer.npz"
GRADER="/app/score_bags.py"

cat > "$GRADER" <<'PY'
"""Streaming observatory event-bag grader.

Scores every patch of a (possibly enormous) bag CSV with the fixed scorer in
/app/scorer.npz and writes one "<bag_id> <positive_count>" line per bag, in
first-occurrence order. Memory stays bounded: the CSV is read in chunks and
only one counter per bag is kept.
"""
import sys

import numpy as np
import pandas as pd

SCORER = "/app/scorer.npz"
DIM = 32
CHUNK = 100_000


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        die("usage: score_bags.py <bag.csv> <out.txt>")
    bag_path, out_path = sys.argv[1], sys.argv[2]

    try:
        z = np.load(SCORER)
        W1, b1, W2, b2 = z["W1"], z["b1"], z["W2"], z["b2"]
    except Exception as exc:
        die("cannot load scorer: %s" % exc)

    feat_cols = ["f%d" % d for d in range(DIM)]
    counts = {}
    order = []

    def tally(bag_ids, pos):
        for bid, p in zip(bag_ids, pos):
            b = int(bid)
            if b not in counts:
                counts[b] = 0
                order.append(b)
            counts[b] += int(p)

    try:
        reader = pd.read_csv(bag_path, chunksize=CHUNK)
        for chunk in reader:
            missing = [c for c in ["bag_id"] + feat_cols if c not in chunk.columns]
            if missing:
                die("bag file missing columns: %s" % ", ".join(missing))
            X = chunk[feat_cols].to_numpy(dtype=np.float64)
            bids = chunk["bag_id"].to_numpy()
            h = np.maximum(X @ W1.T + b1, 0.0)
            zz = (h @ W2.T + b2).ravel()
            tally(bids, zz > 0.0)
    except ValueError as exc:
        die("malformed bag file: %s" % exc)
    except OSError as exc:
        die("cannot read bag file: %s" % exc)

    with open(out_path, "w", encoding="utf-8") as fh:
        for b in order:
            fh.write("%d %d\n" % (b, counts[b]))


if __name__ == "__main__":
    main()
PY

chmod +x "$GRADER"

python3 "$GRADER" /app/data/big_bag.csv /app/event_scores.txt

echo "solve.sh done"
ls -l "$GRADER" /app/event_scores.txt
cat /app/event_scores.txt
