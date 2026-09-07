#!/usr/bin/env python3
"""Optimized petal digest workload.

Same output as digest_slow.py, but carries the accumulator forward instead of
re-walking the prefix, so the cost is linear in the record count.

Usage: python3 digest_fast.py [n]
"""
import sys


def build(n):
    return [{"id": i, "payload": "petal-%05d" % i, "weight": (i * 37) % 101}
            for i in range(n)]


def digest(records):
    out = []
    acc = 0
    for r in records:
        acc = (acc * 31 + r["weight"] + len(r["payload"])) % 1000003
        acc = (acc ^ (r["id"] * 7 + 13)) % 1000003
        out.append("%08x" % acc)
    return out


def main(argv):
    n = int(argv[1]) if len(argv) > 1 else 2000
    lines = digest(build(n))
    sys.stdout.write("%d %s\n" % (len(lines), lines[-1] if lines else "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
