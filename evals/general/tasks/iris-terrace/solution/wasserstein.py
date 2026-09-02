#!/usr/bin/env python3
"""wasserstein.py - sqrt-Wasserstein (a.k.a. 2-Wasserstein metric) distance.

Given a transportation COST matrix C (per-unit movement cost between supply and
demand bins) and a transport PLAN P (amounts moved), the squared transport cost
is the scalar  P . C  (elementwise dot product).  The actual metric distance is
the SQUARE ROOT of that scalar, after rounding/clamping it to be non-negative:

    d = sqrt( max(0, sum_ij P_ij * C_ij) )

The naive mistake is to return the unrooted squared cost (or to take a square
root of a negative number); we always root-clamp first so the result is a valid
distance that compares correctly under metric scaling.

Exposed:
    sqrt_wasserstein(plan, cost) -> float
    CLI: python3 wasserstein.py --plan plan.json --cost cost.json [--out out.json]
"""
import argparse
import json
import sys

import numpy as np


def sqrt_wasserstein(plan, cost):
    """Return sqrt(max(0, sum(plan * cost))) as a float."""
    P = np.asarray(plan, dtype=float)
    C = np.asarray(cost, dtype=float)
    if P.shape != C.shape:
        raise ValueError("plan and cost must have identical shapes (%s vs %s)"
                         % (P.shape, C.shape))
    squared = float(np.sum(P * C))
    squared = max(0.0, squared)
    return float(np.sqrt(squared))


def _load(path):
    with open(path) as f:
        return json.load(f)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True)
    ap.add_argument("--cost", required=True)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    plan = _load(args.plan)
    cost = _load(args.cost)
    d = sqrt_wasserstein(plan, cost)
    if args.out:
        with open(args.out, "w") as f:
            json.dump({"wasserstein": d}, f, indent=2)
    print(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
