#!/bin/bash
# Oracle for basalt-buoy: writes the real planner /app/relay.py (a
# mod-aware segmented DP over the stream with cycle packing), then RUNS it on
# the shipped snapshot to produce /app/plan.json. Never reads /tests.
set -eu

PLANNER="/app/relay.py"
OUT="/app/plan.json"

cat > "$PLANNER" <<'PY'
#!/usr/bin/env python3
"""basalt-buoy drain planner.

Cuts the ordered request stream into consecutive batches whose unit totals are
positive multiples of `granule` and respect batch_cap/fanout, then packs the
batches (in order) into cycles respecting cycle_cap and cycle_max. Finds a
feasible plan via DP over (stream position, open-cycle load) minimising the
number of cycles; any feasible plan is accepted by the contract.
"""
import json
import sys


def plan_stream(budget, requests):
    G = budget["granule"]; B = budget["batch_cap"]; F = budget["fanout"]
    C = budget["cycle_cap"]; M = budget["cycle_max"]
    units = [r["units"] for r in requests]
    ids = [r["id"] for r in requests]
    n = len(units)

    # dp[i][u] = (min closed cycles, parent) with `u` units in the open cycle
    # after the first i requests have been cut into batches.
    dp = [dict() for _ in range(n + 1)]
    dp[0][0] = (0, None)
    for i in range(n):
        if not dp[i]:
            continue
        for u, (closed, _) in list(dp[i].items()):
            s = 0
            for j in range(i, min(n, i + F)):
                s += units[j]
                if s > B:
                    break
                if s % G:
                    continue
                nc = closed + (1 if u > 0 else 0)
                if s <= C:
                    # close the open cycle (if any), start a new one
                    cur = dp[j + 1].get(s)
                    if cur is None or cur[0] > nc:
                        dp[j + 1][s] = (nc, (i, u, i, j + 1))
                if u > 0 and u + s <= C:
                    # append the batch to the currently open cycle
                    cur = dp[j + 1].get(u + s)
                    if cur is None or cur[0] > closed:
                        dp[j + 1][u + s] = (closed, (i, u, i, j + 1))
    if not dp[n]:
        sys.stderr.write("relay: no feasible drain plan\n")
        sys.exit(1)
    best = None
    for u, (closed, _) in dp[n].items():
        total = closed + (1 if u > 0 else 0)
        if best is None or total < best[0]:
            best = (total, u)
    if best[0] > M:
        sys.stderr.write("relay: no plan within cycle_max\n")
        sys.exit(1)

    # backtrack the chosen segmentation
    segs = []
    i, u = n, best[1]
    while i > 0:
        _, par = dp[i][u]
        pi, pu, a, b = par
        segs.append((a, b))
        i, u = pi, pu
    segs.reverse()

    # pack segments into cycles (greedy, in order — matches the DP optimum)
    cycles = []
    cur, cu = [], 0
    for a, b in segs:
        s = sum(units[a:b])
        if cur and cu + s <= C:
            cur.append((a, b)); cu += s
        else:
            if cur:
                cycles.append(cur)
            cur = [(a, b)]; cu = s
    if cur:
        cycles.append(cur)

    out = {"budget": budget, "cycles": []}
    for k, cyc in enumerate(cycles):
        entry = {"cycle_id": "c%d" % k, "units": 0, "batches": []}
        tot = 0
        for m, (a, b) in enumerate(cyc):
            s = sum(units[a:b]); tot += s
            entry["batches"].append({
                "batch_id": "c%d-b%d" % (k, m),
                "requests": ids[a:b],
                "units": s,
            })
        entry["units"] = tot
        out["cycles"].append(entry)
    return out


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: relay.py <requests.json> <plan.json>\n")
        sys.exit(2)
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        data = json.load(fh)
    result = plan_stream(data["budget"], data["requests"])
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$PLANNER"

# Run the planner on the shipped snapshot to produce the deliverable plan.
python3 "$PLANNER" /app/input/requests.json "$OUT"

echo "solve.sh done -> $PLANNER and $OUT"
ls -l "$PLANNER" "$OUT"
