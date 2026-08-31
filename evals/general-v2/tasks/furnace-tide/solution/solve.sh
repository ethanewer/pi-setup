#!/bin/bash
# Oracle for furnace-tide: write the streaming scorer, then RUN it on the
# visible trace set to produce /app/trace_scores.txt. Never reads /tests.
set -eu

SCORER="/app/score_traces.py"
OUT="/app/trace_scores.txt"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SCORER" <<'PY'
import sys

import numpy as np
import pandas as pd

np.seterr(all="ignore")

F = 32
FEATS = [f"x{i}" for i in range(F)]
MODEL = "/app/model.npz"
CHUNK = 8192


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def main():
    if len(sys.argv) != 3:
        fail("usage: score_traces.py <traces.csv> <out.txt>")
    in_path, out_path = sys.argv[1], sys.argv[2]
    try:
        m = np.load(MODEL)
        W1, b1, W2, b2 = m["W1"], m["b1"], m["W2"], m["b2"]
    except Exception as e:
        fail(f"cannot load model: {e}")
    try:
        header = pd.read_csv(in_path, nrows=0).columns.tolist()
    except Exception as e:
        fail(f"unreadable input: {e}")
    missing = [c for c in ["trace_id"] + FEATS if c not in header]
    if missing:
        fail(f"input missing columns: {missing}")

    order, sums, cnts = [], {}, {}
    try:
        for chunk in pd.read_csv(in_path, chunksize=CHUNK):
            X = chunk[FEATS].to_numpy(dtype=np.float64)
            if not np.isfinite(X).all():
                fail("non-finite feature value in input")
            h = np.maximum(X @ W1.T + b1, 0.0)
            p = 1.0 / (1.0 + np.exp(-(h @ W2.T + b2).ravel()))
            tids = chunk["trace_id"].astype(str).to_numpy()
            for tid, pv in zip(tids, p):
                if tid in sums:
                    sums[tid] += pv
                    cnts[tid] += 1
                else:
                    sums[tid] = float(pv)
                    cnts[tid] = 1
                    order.append(tid)
    except ValueError as e:
        fail(f"bad numeric value in input: {e}")

    lines = ["%.4f" % (sums[tid] / cnts[tid]) for tid in order]
    text = "".join(l + "\n" for l in lines)
    sys.stdout.write(text)
    with open(out_path, "w") as fh:
        fh.write(text)


if __name__ == "__main__":
    main()
PY

chmod +x "$SCORER"

# 2. Run the produced program on the visible trace set to generate the artifact.
python3 "$SCORER" /app/data/traces_visible.csv "$OUT"

echo "solve.sh done -> $SCORER and $OUT"
ls -l "$SCORER" "$OUT"
