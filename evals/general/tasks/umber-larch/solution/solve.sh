#!/bin/bash
# Real oracle for umber-larch: writes the ATE estimator (/app/estimate.py) and
# runs it on the visible study to produce /app/answer.txt. Never reads /tests.
# Optional args (authoring-time cross-checks):
#   bash solve.sh <obs.csv> <dag.json> <out.txt>
set -eu

OBS="${1:-/app/obs.csv}"
DAG="${2:-/app/dag.json}"
OUT="${3:-/app/answer.txt}"

SOLVER="/app/estimate.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Backdoor-adjusted g-computation ATE estimator (numpy only)."""
import csv
import json
import sys

import numpy as np


def read_table(path):
    with open(path, newline="") as fh:
        rdr = csv.reader(fh)
        header = next(rdr)
        rows = [[float(x) for x in r] for r in rdr if r]
    cols = {name: np.array([r[j] for r in rows]) for j, name in enumerate(header)}
    return header, cols


def main(obs_path, dag_path, out_path):
    header, cols = read_table(obs_path)
    with open(dag_path) as fh:
        dag = json.load(fh)
    T = dag["treatment_column"]
    Y = dag["outcome_column"]
    edges = [tuple(e) for e in dag["edges"]]

    t = cols[T]
    y = cols[Y]

    # ---- adjustment set: parents of T that still reach Y with T deleted ----
    parents = sorted({p for p, c in edges if c == T})
    # graph with T and all its edges removed
    edges_no_T = [(p, c) for p, c in edges if p != T and c != T]
    children = {}
    for p, c in edges_no_T:
        children.setdefault(p, []).append(c)

    def reaches(start, target):
        seen = {start}
        stack = [start]
        while stack:
            u = stack.pop()
            if u == target:
                return True
            for v in children.get(u, ()):
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        return False

    adj = [p for p in parents if reaches(p, Y)]

    # ---- design: [1, t, adj vars, t*adj, squares of continuous adj] --------
    n = len(t)
    feats = [np.ones(n), t]
    for name in adj:
        v = cols[name]
        feats.append(v)
    for name in adj:
        feats.append(t * cols[name])
    for name in adj:
        v = cols[name]
        if len(np.unique(v)) > 2:
            feats.append(v * v)
    X = np.stack(feats, axis=1)

    beta, *_ = np.linalg.lstsq(X, y, rcond=None)

    # ---- g-computation ------------------------------------------------------
    X1 = X.copy(); X1[:, 1] = 1.0
    X0 = X.copy(); X0[:, 1] = 0.0
    for k, name in enumerate(adj):
        X1[:, 2 + len(adj) + k] = cols[name]         # t=1 * v = v
        X0[:, 2 + len(adj) + k] = 0.0                # t=0 * v = 0
    ate = float(np.mean(X1 @ beta) - np.mean(X0 @ beta))

    with open(out_path, "w") as fh:
        fh.write("%.6f\n" % ate)
    print("ESTIMATE_OK adj=%s ate=%.6f" % (",".join(adj), ate))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.stderr.write("usage: estimate.py <obs.csv> <dag.json> <out.txt>\n")
        sys.exit(2)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
PY

chmod +x "$SOLVER"

# ---- 2. Run the produced estimator on the requested study ------------------
python3 "$SOLVER" "$OBS" "$DAG" "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
cat "$OUT"
