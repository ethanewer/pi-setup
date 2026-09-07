#!/usr/bin/env python3
"""Optimized petal refine workload.

Same output as refine_slow.py, but builds the per-tag best score once with a
single pass instead of re-scanning the table per candidate, so the cost is
linear in the record count apart from the final sort.

Usage: python3 refine_fast.py [n]
"""
import sys


def build(n):
    return [{"id": i, "tag": "t%03d" % (i % 29), "score": (i * 53) % 977}
            for i in range(n)]


def refine(records):
    best_by_tag = {}
    for r in records:
        s = r["score"]
        if s > best_by_tag.get(r["tag"], 0):
            best_by_tag[r["tag"]] = s
    kept = [(r["tag"], r["score"]) for r in records
            if r["score"] * 2 >= best_by_tag[r["tag"]]]
    kept.sort()
    return kept


def main(argv):
    n = int(argv[1]) if len(argv) > 1 else 2000
    rows = refine(build(n))
    sys.stdout.write("%d %s\n" % (len(rows), rows[-1] if rows else "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
