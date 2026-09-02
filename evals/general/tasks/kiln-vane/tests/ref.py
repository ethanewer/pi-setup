#!/usr/bin/env python3
"""Reference oracle for kiln-vane. Never hard-codes an input: recomputes the
6x6 swatch from the operating rule for whatever tile it is given.

Usage:
  ref.py weave <tile.json>            # prints the expected 6x6 as JSON
  ref.py swatch <tile.json> <out>     # compares an agent swatch to the rule
"""
import json
import sys

N = 6


def expected(tile):
    tiled = [[tile[r % 2][c % 2] for c in range(N)] for r in range(N)]
    hshift = [[tiled[r][(c - ((r + 1) % 3)) % N] for c in range(N)]
              for r in range(N)]
    return [[hshift[(r + ((c + 2) % 3)) % N][c] for c in range(N)]
            for r in range(N)]


def main():
    mode = sys.argv[1]
    with open(sys.argv[2]) as fh:
        tile = json.load(fh)["tile"]
    want = expected(tile)
    if mode == "weave":
        print(json.dumps(want))
        return 0
    with open(sys.argv[3]) as fh:
        got = json.load(fh)
    ok = (isinstance(got, list) and len(got) == N
          and all(isinstance(r, list) and len(r) == N
                  and all(isinstance(v, int) for v in r) for r in got)
          and got == want)
    print("MATCH" if ok else "MISMATCH")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
