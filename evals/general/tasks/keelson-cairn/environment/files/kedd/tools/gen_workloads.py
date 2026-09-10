#!/usr/bin/env python3
"""Deterministic generator for kedd workload fixtures.

kedd daemon workloads are plain-text event lists, one event per line:

    <ordinal>,<payload>,<width>

    ordinal  - event ordinal, must run 0..N-1 contiguously in file order
    payload  - an opaque token, chars in [A-Za-z0-9._-], non-empty
    width    - integer 0..2000, the unit processing cost of the event
               (the daemon parks ~25 microseconds per unit)

Lines beginning with '#' and blank lines are comments and are ignored.

The generator is deterministic: the same (shape, seed) always yields the
same bytes, which is what makes the fixtures reproducible and pin-able.
"""

import argparse
import random
import sys

WORDS = [
    "raven", "toll", "fog", "gale", "swell", "tide", "holm", "reef",
    "skerry", "bluff", "course", "light", "bell", "boom", "spar", "keel",
    "bar", "cove", "dune", "floe",
]


def payload(rng, i):
    token = "%s-%03d" % (rng.choice(WORDS), i)
    if i % 11 == 0:
        token = "_" + token
    return token


def write_workload(path, seed, n, widths, note):
    rng = random.Random(seed)
    lines = [
        "# kedd workload - one event per line: ordinal,payload,width",
        "# %s" % note,
        "# seed=%d n=%d (deterministic)" % (seed, n),
        "",
    ]
    total = 0
    for i in range(n):
        w = widths(rng, i)
        total += w
        lines.append("%d,%s,%d" % (i, payload(rng, i), w))
    lines.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("wrote %-8s n=%-5d total_units=%-7d (%s)" %
          (path, n, total, note))


def uniform(rng, i, lo=100, hi=1750):
    return rng.randint(lo, hi)


def stream(rng, i):
    return rng.randint(60, 1500)


def tail_burst(rng, i, base_n=700):
    if i >= base_n:
        return rng.randint(1600, 1990)
    return rng.randint(80, 520)


def mixed(rng, i):
    if i % 2 == 0:
        return rng.randint(60, 250)
    return rng.randint(900, 1950)


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("shape", choices=["sample", "h1", "h2", "h3"])
    p.add_argument("out", help="output path for workload.txt")
    args = p.parse_args(argv)

    if args.shape == "sample":
        write_workload(args.out, seed=271828, n=900,
                       widths=uniform,
                       note="visible sample: uniform widths, 9 events per 10")
    elif args.shape == "h1":
        write_workload(args.out, seed=314159, n=1300,
                       widths=stream,
                       note="hidden: high-volume streaming, narrow widths")
    elif args.shape == "h2":
        write_workload(args.out, seed=90210, n=960,
                       widths=tail_burst,
                       note="hidden: long quiet run then a burst of wide events")
    elif args.shape == "h3":
        write_workload(args.out, seed=424242, n=1100,
                       widths=mixed,
                       note="hidden: alternating narrow and wide events")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))