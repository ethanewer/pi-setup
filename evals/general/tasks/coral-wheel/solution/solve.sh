#!/bin/bash
# Real oracle for coral-wheel. Writes the /app/solve.py deliverable (a genuine
# constrained-allocation solver), then RUNS it on /app/portfolio.json to
# produce /app/allocation.json. Does not read /tests and never cats a
# precomputed answer.
set -eu

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Constrained-allocation solver.

Usage: python3 solve.py <input_portfolio.json> <output_result.json>
Reads a portfolio document and writes the optimal allocation (lexicographic
objective: maximize return, then minimize risk, then minimize item count).
"""
import json
import sys

NEG = -10 ** 12


def solve(portfolio):
    budget = int(portfolio['budget'])
    rlim = int(portfolio['risk_limit'])
    mret = int(portfolio['min_return'])
    items = portfolio['items']
    names = [it['name'] for it in items]
    n = len(names)

    # state[c][r] = [max_return, min_item_count, quantities]
    state = [[[NEG, 10 ** 9, None] for _ in range(rlim + 1)]
             for _ in range(budget + 1)]
    state[0][0] = [0, 0, [0] * n]

    for t, it in enumerate(items):
        cost, risk, val = int(it['cost']), int(it['risk']), int(it['return'])
        if cost == 0 and risk == 0:
            continue  # a free, reward-free item is never worth taking
        for c in range(budget + 1):
            for r in range(rlim + 1):
                pc, pr = c - cost, r - risk
                if pc < 0 or pr < 0:
                    continue
                old = state[pc][pr]
                if old[0] == NEG:
                    continue
                nr, nc = old[0] + val, old[1] + 1
                cur = state[c][r]
                if cur[0] == NEG or nr > cur[0] or (nr == cur[0] and nc < cur[1]):
                    q = list(old[2])
                    q[t] += 1
                    state[c][r] = [nr, nc, q]

    best = None
    for c in range(budget + 1):
        for r in range(rlim + 1):
            st = state[c][r]
            if st[0] == NEG or st[0] < mret:
                continue
            cand = (st[0], r, st[1], c, st[2])
            if best is None or cand[0] > best[0] or \
               (cand[0] == best[0] and cand[1] < best[1]) or \
               (cand[0] == best[0] and cand[1] == best[1] and cand[2] < best[2]):
                best = cand

    if best is None:
        return {"infeasible": True, "quantities": {}}

    ret, risk, cnt, cost, q = best
    return {
        "cost": cost,
        "risk": risk,
        "return": ret,
        "item_count": cnt,
        "quantities": {names[i]: q[i] for i in range(n)},
    }


def main():
    inp = sys.argv[1] if len(sys.argv) > 1 else '/app/portfolio.json'
    out = sys.argv[2] if len(sys.argv) > 2 else '/app/allocation.json'
    with open(inp) as f:
        portfolio = json.load(f)
    with open(out, 'w') as f:
        json.dump(solve(portfolio), f, indent=2, sort_keys=True)


if __name__ == '__main__':
    main()
PY

python3 /app/solve.py /app/portfolio.json /app/allocation.json