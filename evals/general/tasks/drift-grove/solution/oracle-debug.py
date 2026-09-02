#!/usr/bin/env python3
"""Grove oracle debugger: locate the drift-log length by binary search.

usage: oracle-debug.py <ctx>

Probes the observe oracle (both endpoints) under a strict call budget:
  - 'span': monotone existence predicate over log positions -> binary-searchable
  - 'leaf': reads an entry / confirms the EOF marker
Writes:
  /app/lines.txt        the detected log length (the number only)
  /app/probe-log.json   debugging transcript {answer, calls, budget, probes[]}
"""
import json
import os
import subprocess
import sys

BUDGET = 40
OBSERVE = os.environ.get("OBSERVE_PATH", "/app/bin/observe")
LINES_OUT = os.environ.get("LINES_OUT", "/app/lines.txt")
LOG_OUT = os.environ.get("LOG_OUT", "/app/probe-log.json")


def main() -> int:
    ctx = sys.argv[1]
    probes = []

    def span(k):
        reply = subprocess.run(
            [OBSERVE, ctx, "span", str(k)], capture_output=True, text=True
        ).stdout.strip()
        probes.append({"endpoint": "span", "k": k, "reply": reply, "kind": "size"})
        return reply == "1"

    def leaf(k):
        reply = subprocess.run(
            [OBSERVE, ctx, "leaf", str(k)], capture_output=True, text=True
        ).stdout.strip()
        probes.append({"endpoint": "leaf", "k": k, "reply": reply, "kind": "content"})
        return reply

    def over():
        return len(probes) > BUDGET

    # 1) exponential bracket: double hi until a missing position is found
    lo, hi = 0, 1
    while span(hi) and not over():
        lo, hi = hi, hi * 2
    if over() or span(hi):
        raise SystemExit("budget exhausted while bracketing the drift log")
    # 2) binary search the first missing position in (lo, hi]
    while lo + 1 < hi and not over():
        mid = (lo + hi) // 2
        if span(mid):
            lo = mid
        else:
            hi = mid
    if over():
        raise SystemExit("budget exhausted while binary searching")
    ans = lo + 1  # last existing position index == lo, count == lo + 1

    # confirm the boundary through the content endpoint
    if leaf(ans) != "-EOF":
        raise SystemExit("EOF check failed at detected length %d" % ans)

    with open(LINES_OUT, "w") as fh:
        fh.write("%d\n" % ans)
    with open(LOG_OUT, "w") as fh:
        json.dump(
            {
                "answer": ans,
                "calls": len(probes),
                "budget": BUDGET,
                "problem": "drift-log-length",
                "probes": probes,
            },
            fh,
            indent=1,
        )
    return 0


if __name__ == "__main__":
    main()