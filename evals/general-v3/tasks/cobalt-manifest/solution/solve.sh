#!/bin/bash
# Real oracle for cobalt-manifest: writes the /app/solve.py deliverable (a
# genuine equality-constrained integer-program solver), then RUNS it on
# /app/manifest.json to produce /app/manifest_result.json. Never reads /tests.
set -eu
mkdir -p /app

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Cobalt resupply manifest solver (exact integer program).

Usage: python3 solve.py <input_manifest.json> <output_result.json>

Decision variables: nonnegative integer quantities q_i per cargo entry.
Hard constraints (all exact integer arithmetic):
  sum(q_i) == containers        (equality-sum)
  sum(q_i * mass_i) == mass     (equality-sum)
  sum(q_i * volume_i) <= volume_limit
Objective: minimize cost, then maximize science, then lexicographically
smallest quantity vector in input cargo order.
"""
import json
import sys


def solve(manifest):
    K = int(manifest["containers"])
    W = int(manifest["mass"])
    V = int(manifest["volume_limit"])
    cargo = manifest["cargo"]
    n = len(cargo)

    # reach[i] = set of (count, mass) sums achievable with items i..n-1
    reach = [set() for _ in range(n + 1)]
    reach[n].add((0, 0))
    for i in range(n - 1, -1, -1):
        m = int(cargo[i]["mass"])
        acc = set()
        for (k, w) in reach[i + 1]:
            q = 0
            while True:
                k2, w2 = k + q, w + q * m
                if k2 > K or w2 > W:
                    break
                acc.add((k2, w2))
                q += 1
        reach[i] = acc

    best = None   # (cost, -science, q-tuple)
    best_q = None

    # Iterative DFS with reachability pruning.
    stack = [(0, 0, 0, 0, 0, [])]  # i, count, mass, cost, science, qlist
    qlist = []

    def dfs(i, k, w, cost, science, volume):
        nonlocal best, best_q
        if i == n:
            if k == K and w == W and volume <= V:
                cand = (cost, -science, tuple(qlist))
                if best is None or cand < best:
                    best = cand
                    best_q = list(qlist)
            return
        m = int(cargo[i]["mass"])
        q = 0
        while True:
            k2, w2 = k + q, w + q * m
            if k2 > K or w2 > W:
                break
            if (K - k2, W - w2) in reach[i + 1]:
                qlist.append(q)
                dfs(i + 1, k2, w2,
                    cost + q * int(cargo[i]["cost"]),
                    science + q * int(cargo[i]["science"]),
                    volume + q * int(cargo[i]["volume"]))
                qlist.pop()
            q += 1

    dfs(0, 0, 0, 0, 0, 0)

    if best is None:
        return {"infeasible": True, "quantities": {}}

    quantities = {c["name"]: q for c, q in zip(cargo, best_q)}
    volume = sum(int(c["volume"]) * q for c, q in zip(cargo, best_q))
    return {
        "cost": best[0],
        "science": -best[1],
        "mass": W,
        "volume": volume,
        "quantities": quantities,
    }


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: solve.py <input_manifest.json> <output_result.json>\n")
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    result = solve(manifest)
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, sort_keys=True)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x /app/solve.py

python3 /app/solve.py /app/manifest.json /app/manifest_result.json

echo "solve.sh done"
cat /app/manifest_result.json
