#!/bin/bash
# Real oracle for basalt-lattice: write the reusable solver (structure recovery
# per the documented heuristics), then RUN it on the visible fixtures to produce
# /app/recovered_edges.csv and /app/fit.csv. Never reads /tests.
set -eu

SOLVER="/app/solver.py"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""RelayGrid structure recovery: max-|r| spanning tree + root orientation."""
import csv
import json
import math
import sys

TOL = 1e-9


def read_samples(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    data = {h: [] for h in header}
    for r in rows[1:]:
        if not r:
            continue
        for h, v in zip(header, r):
            data[h].append(float(v))
    return data


def pearson(x, y):
    n = len(x)
    mx = sum(x) / n
    my = sum(y) / n
    dx = [a - mx for a in x]
    dy = [a - my for a in y]
    sxy = sum(a * b for a, b in zip(dx, dy))
    sxx = sum(a * a for a in dx)
    syy = sum(b * b for b in dy)
    return sxy / math.sqrt(sxx * syy)


def partial_corr(r_vp, r_vq, r_pq):
    num = r_vp - r_vq * r_pq
    den = math.sqrt((1.0 - r_vq * r_vq) * (1.0 - r_pq * r_pq))
    if den == 0.0 or not math.isfinite(den):
        return None
    return num / den


def recover(data, cols, root, edge_count):
    n = len(cols)
    idx = {c: i for i, c in enumerate(cols)}
    R = {}
    for i, a in enumerate(cols):
        for b in cols[i + 1:]:
            R[(a, b)] = R[(b, a)] = pearson(data[a], data[b])

    included = [cols[0]]
    undirected = []
    while len(included) < n:
        cands = [(u, v) for u in included for v in cols if v not in included]
        best = max(abs(R[(u, v)]) for u, v in cands)
        tied = [(u, v) for u, v in cands if abs(R[(u, v)]) >= best - TOL]
        tied.sort(key=lambda e: (idx[e[1]], idx[e[0]]))
        children = {v for _, v in tied}
        if len(children) == 1 and len({u for u, _ in tied}) > 1:
            # analogical child rule: one child, several candidate parents
            v = tied[0][1]
            parents = sorted({u for u, _ in tied}, key=lambda p: idx[p])
            if len(parents) == 2:
                p, q = parents
                pc_p = partial_corr(R[(v, p)], R[(v, q)], R[(p, q)])
                pc_q = partial_corr(R[(v, q)], R[(v, p)], R[(p, q)])
                if pc_p is None or pc_q is None:
                    u = parents[0]
                elif pc_p > pc_q + TOL:
                    u = p
                elif pc_q > pc_p + TOL:
                    u = q
                else:
                    u = parents[0]
            else:
                # >2 tied parents: pick earliest with defined maximal partial corr
                scores = {}
                undefined = False
                for p in parents:
                    vals = []
                    for q in parents:
                        if q == p:
                            continue
                        c = partial_corr(R[(v, p)], R[(v, q)], R[(p, q)])
                        if c is None:
                            undefined = True
                        vals.append(c)
                    scores[p] = None if undefined else min(vals)
                if undefined:
                    u = parents[0]
                else:
                    best_pc = max(scores.values())
                    u = min(p for p in parents if scores[p] >= best_pc - TOL)
            undirected.append((u, v))
            included.append(v)
            continue
        u, v = tied[0]
        undirected.append((u, v))
        included.append(v)

    if len(undirected) != edge_count:
        raise SystemExit("edge count mismatch: %d != %d" % (len(undirected), edge_count))

    adj = {c: [] for c in cols}
    for a, b in undirected:
        adj[a].append(b)
        adj[b].append(a)
    directed = []
    seen = {root}
    queue = [root]
    while queue:
        nxt = []
        for p in queue:
            for c in sorted(adj[p], key=lambda x: idx[x]):
                if c not in seen:
                    seen.add(c)
                    directed.append((p, c))
                    nxt.append(c)
        queue = nxt
    if len(seen) != n:
        raise SystemExit("tree not connected from root")
    return sorted(directed, key=lambda e: (idx[e[0]], idx[e[1]]))


def ols_slope(data, parent, child):
    xs, ys = data[parent], data[child]
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
    sxx = sum((a - mx) ** 2 for a in xs)
    return sxy / sxx


def main():
    samples, spec_path, edges_out, fit_out = sys.argv[1:5]
    data = read_samples(samples)
    with open(spec_path) as f:
        spec = json.load(f)
    edges = recover(data, spec["network_columns"], spec["root"], spec["edge_count"])
    with open(edges_out, "w", newline="") as f:
        f.write("parent,child\n")
        for p, c in edges:
            f.write("%s,%s\n" % (p, c))
    with open(fit_out, "w", newline="") as f:
        f.write("parent,child,slope\n")
        for p, c in edges:
            f.write("%s,%s,%.6f\n" % (p, c, ols_slope(data, p, c)))


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/samples.csv /app/spec.json /app/recovered_edges.csv /app/fit.csv

echo "solve.sh done"
cat /app/recovered_edges.csv /app/fit.csv
