#!/bin/bash
# Oracle for coral-trellis: writes the real structure-learning solver (max-|r|
# Prim skeleton + root-constraint BFS orientation) to /app/solver.py, then RUNS
# it on the visible fixtures to produce /app/recovered_edges.csv. Never reads /tests.
set -eu

SOLVER="/app/solver.py"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""BeaconGrid mesh forensics: recover the propagation DAG from telemetry.

Heuristics (applied exactly, in order):
  1. pairwise Pearson correlation over the spec's columns;
  2. maximum-|r| spanning tree via Prim (start columns[0], max |r| across the
     cut, ties broken by smallest (i, j) index pair in spec column order);
  3. orient every skeleton edge away from the spec root (BFS);
  4. child-analogy rule: siblings are conditionally independent given their
     shared parent; with a unique root and a tree skeleton this fixes every
     direction, so the BFS orientation is final.
"""
import csv
import json
import math
import os
import sys
from collections import deque


def read_matrix(path):
    with open(path, "r", newline="") as fh:
        rd = csv.reader(fh)
        header = next(rd)
        rows = [[float(v) for v in row] for row in rd if row]
    return header, rows


def pearson_matrix(rows, ncols):
    n = len(rows)
    means = [sum(r[c] for r in rows) / n for c in range(ncols)]
    # centered second-moment sums (scale cancels in the correlation ratio)
    cov = [[0.0] * ncols for _ in range(ncols)]
    for r in rows:
        dx = [r[c] - means[c] for c in range(ncols)]
        for i in range(ncols):
            di = dx[i]
            row = cov[i]
            for j in range(i, ncols):
                row[j] += di * dx[j]
    for i in range(ncols):
        for j in range(i + 1, ncols):
            cov[j][i] = cov[i][j]
    R = [[0.0] * ncols for _ in range(ncols)]
    for i in range(ncols):
        for j in range(ncols):
            denom = math.sqrt(cov[i][i] * cov[j][j])
            R[i][j] = cov[i][j] / denom if denom > 0 else 0.0
    return R


def max_spanning_tree(R, n):
    """Prim over complete graph; start at node 0; max |r| across the cut;
    tie-break by smallest (min(i,j), max(i,j)) index pair."""
    in_tree = {0}
    tree = []
    while len(in_tree) < n:
        best = None  # (key, i, j)
        for i in sorted(in_tree):
            for j in range(n):
                if j in in_tree:
                    continue
                key = (-abs(R[i][j]), min(i, j), max(i, j))
                if best is None or key < best[0]:
                    best = (key, i, j)
        _, i, j = best
        tree.append((i, j))
        in_tree.add(j)
    return tree


def main():
    data_path, spec_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    columns = list(spec["columns"])
    root = spec["root"]
    edge_count = int(spec["edge_count"])

    header, rows = read_matrix(data_path)
    col_idx = {name: header.index(name) for name in columns}
    ncols = len(columns)
    # project rows into spec column order
    proj = [[r[col_idx[c]] for c in columns] for r in rows]
    R = pearson_matrix(proj, ncols)

    tree = max_spanning_tree(R, ncols)
    if len(tree) != edge_count:
        raise SystemExit(
            "recovered skeleton has %d edges, spec demands %d"
            % (len(tree), edge_count))

    # adjacency
    adj = {i: [] for i in range(ncols)}
    for i, j in tree:
        adj[i].append(j)
        adj[j].append(i)

    # orient away from the root (unique source)
    if root not in col_idx and root not in columns:
        raise SystemExit("root %r not among columns" % root)
    src = columns.index(root)
    edges = []
    seen = {src}
    q = deque([src])
    while q:
        u = q.popleft()
        for v in adj[u]:
            if v not in seen:
                seen.add(v)
                edges.append((columns[u], columns[v]))
                q.append(v)
    if len(seen) != ncols:
        raise SystemExit("skeleton not connected from root")

    edges.sort()
    if not os.path.isdir(outdir):
        os.makedirs(outdir, exist_ok=True)
    with open(outdir.rstrip("/") + "/recovered_edges.csv", "w", newline="") as fh:
        fh.write("parent,child\n")
        for p, c in edges:
            fh.write("%s,%s\n" % (p, c))
    print("SOLVER_OK %d edges" % len(edges))


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced solver on the visible fixtures to create the deliverable.
python3 "$SOLVER" /app/telemetry.csv /app/spec.json /app

[ -f /app/recovered_edges.csv ] || { echo "oracle: missing /app/recovered_edges.csv" >&2; exit 1; }
echo "solve.sh done"
cat /app/recovered_edges.csv
