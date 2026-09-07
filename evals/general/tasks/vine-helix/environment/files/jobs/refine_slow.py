#!/usr/bin/env python3
"""Slow petal refine workload.

Selects the records worth keeping by re-scanning the whole table for every
candidate and rebuilding the sort key from scratch each time, so the cost is
quadratic in the record count. This is the unoptimized variant the task asks the
agent to profile against refine_fast.py.

Usage: python3 refine_slow.py [n]
"""
import sys


def build(n):
    return [{"id": i, "tag": "t%03d" % (i % 29), "score": (i * 53) % 977}
            for i in range(n)]


def refine(records):
    kept = []
    for r in records:
        # re-scan the whole table to rank this candidate instead of keeping a
        # running index
        peers = [q for q in records if q["tag"] == r["tag"]]
        best = 0
        for q in peers:
            if q["score"] > best:
                best = q["score"]
        if r["score"] * 2 >= best:
            kept.append((r["tag"], r["score"]))
    kept.sort()
    return kept


def main(argv):
    n = int(argv[1]) if len(argv) > 1 else 2000
    rows = refine(build(n))
    sys.stdout.write("%d %s\n" % (len(rows), rows[-1] if rows else "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
