#!/bin/bash
# Oracle: writes /app/solve.py (the real program) and runs it on the visible
# inputs to produce /app/answer.json. Does not read /tests and cats nothing.
set -eu

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Lexicographic topological order + post-intervention values for a DAG.

Usage:
  solve.py --graph <graph.csv> --values <values.csv>
           [--intervention n=v,n=v ...] --output <out.json>
"""
import sys
import heapq
import json
from decimal import Decimal, ROUND_HALF_UP

Q = Decimal("1e-6")


def rounded(value):
    return float(value.quantize(Q, rounding=ROUND_HALF_UP))


def read_graph(path):
    children = {}
    indeg = {}
    with open(path) as f:
        next(f, None)                      # header
        for line in f:
            line = line.strip()
            if not line:
                continue
            p, c = line.split(",")
            p, c = p.strip(), c.strip()
            children.setdefault(p, []).append(c)
            indeg[c] = indeg.get(c, 0) + 1
            indeg.setdefault(p, 0)
    return children, indeg


def read_values(path, nodes):
    base = {}
    names = set()
    with open(path) as f:
        next(f, None)                      # header
        for line in f:
            line = line.strip()
            if not line:
                continue
            node, val = line.split(",")
            node, val = node.strip(), val.strip()
            names.add(node)
            base[node] = Decimal(val)
    for n in nodes:
        base.setdefault(n, Decimal("0"))
    return base, names


def main():
    argv = sys.argv[1:]
    graph = values = output = None
    intervention = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--graph":
            graph = argv[i + 1]; i += 2
        elif a == "--values":
            values = argv[i + 1]; i += 2
        elif a == "--output":
            output = argv[i + 1]; i += 2
        elif a == "--intervention":
            intervention += [x for x in argv[i + 1].split(",") if x.strip()]
            i += 2
        else:
            raise SystemExit("unknown arg: %s" % a)
    if not (graph and values and output):
        raise SystemExit("need --graph --values --output")

    children, indeg = read_graph(graph)
    graph_nodes = set(children) | set(indeg) | {c for x in children.values() for c in x}
    base, names = read_values(values, graph_nodes)
    nodes = sorted(graph_nodes | names)

    iv = {}
    for pair in intervention:
        node, val = pair.split("=")
        node, val = node.strip(), val.strip()
        if node in nodes:
            iv[node] = Decimal(val)

    # Lexicographic topological order via Kahn with a min-heap.
    d = dict(indeg)
    for n in nodes:
        d.setdefault(n, 0)
    ready = [n for n in nodes if d[n] == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        n = heapq.heappop(ready)
        order.append(n)
        for c in children.get(n, []):
            d[c] -= 1
            if d[c] == 0:
                heapq.heappush(ready, c)
    acyclic = len(order) == len(nodes)

    if not acyclic:
        result = {"acyclic": False, "intervention": None,
                  "order": None, "values": None}
    else:
        vals = {}
        for n in order:
            if n in iv:
                vals[n] = iv[n]
            else:
                s = base[n] if n in base else Decimal("0")
                for p in nodes:
                    if n in children.get(p, []):
                        s += Decimal("0.5") * vals[p]
                vals[n] = s
        result = {
            "acyclic": True,
            "intervention": {k: rounded(v) for k, v in sorted(iv.items())},
            "order": order,
            "values": {k: rounded(v) for k, v in vals.items()},
        }

    with open(output, "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
PY
chmod +x /app/solve.py

python3 /app/solve.py \
  --graph /app/graph.csv --values /app/values.csv \
  --intervention left=10 --output /app/answer.json

echo "oracle done: wrote /app/solve.py and /app/answer.json"