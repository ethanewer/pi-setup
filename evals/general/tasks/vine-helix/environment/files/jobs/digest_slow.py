#!/usr/bin/env python3
"""Slow petal digest workload.

Recomputes the running digest over the whole prefix at every step, so the cost
is quadratic in the record count. This is the unoptimized variant the task asks
the agent to profile against digest_fast.py.

Usage: python3 digest_slow.py [n]
"""
import sys


def build(n):
    return [{"id": i, "payload": "petal-%05d" % i, "weight": (i * 37) % 101}
            for i in range(n)]


def digest(records):
    out = []
    for i in range(len(records)):
        acc = 0
        # re-walk the prefix from the beginning on every iteration
        for r in records[:i + 1]:
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
