#!/usr/bin/env python3
"""GridSense reference solver: recover the directed fault-propagation DAG.

Implements exactly the heuristic documented in instruction.md:
  1. load spec columns, 2. pairwise Pearson, 3. max-|r| spanning tree via
  union-find with key (-|r|, i, j), 4. BFS orientation away from the root,
  5. directed_hints flip conflicts.
"""
import csv
import json
import sys
from collections import deque


def pearson(xs, ys):
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxy = sxx = syy = 0.0
    for x, y in zip(xs, ys):
        dx = x - mx
        dy = y - my
        sxy += dx * dy
        sxx += dx * dx
        syy += dy * dy
    return sxy / ((sxx * syy) ** 0.5)


def main():
    telemetry_path, spec_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    columns = list(spec["columns"])
    root = spec["root"]
    edge_count = int(spec["edge_count"])
    hints = spec.get("directed_hints") or []

    colvals = {c: [] for c in columns}
    with open(telemetry_path, "r", encoding="utf-8", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        pos = {name: k for k, name in enumerate(header)}
        for row in reader:
            if not row:
                continue
            for c in columns:
                colvals[c].append(float(row[pos[c]]))

    n = len(columns)
    idx = {c: i for i, c in enumerate(columns)}
    pairs = []
    for i in range(n):
        for j in range(i + 1, n):
            r = pearson(colvals[columns[i]], colvals[columns[j]])
            pairs.append((-abs(r), i, j))
    pairs.sort()

    parent_of = list(range(n))

    def find(a):
        while parent_of[a] != a:
            parent_of[a] = parent_of[parent_of[a]]
            a = parent_of[a]
        return a

    skeleton = []
    for _, i, j in pairs:
        if len(skeleton) == edge_count:
            break
        ri, rj = find(i), find(j)
        if ri != rj:
            parent_of[ri] = rj
            skeleton.append((i, j))

    adj = {i: [] for i in range(n)}
    for i, j in skeleton:
        adj[i].append(j)
        adj[j].append(i)

    ridx = idx[root]
    seen = {ridx}
    q = deque([ridx])
    directed = set()
    while q:
        u = q.popleft()
        for v in sorted(adj[u]):
            if v not in seen:
                seen.add(v)
                directed.add((u, v))
                q.append(v)

    for p, c in hints:
        if p in idx and c in idx:
            a, b = idx[p], idx[c]
            edge = (a, b) if a < b else (b, a)
            if edge in skeleton and (b, a) in directed:
                directed.discard((b, a))
                directed.add((a, b))

    rows = sorted((columns[p], columns[c]) for p, c in directed)
    with open(out_path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["parent", "child"])
        for p, c in rows:
            writer.writerow([p, c])


if __name__ == "__main__":
    main()
