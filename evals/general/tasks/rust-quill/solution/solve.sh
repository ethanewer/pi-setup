#!/bin/bash
# Oracle for rust-quill: write the emd_distance.py module, then RUN its CLI on
# the visible fixtures to produce /app/distance.json. Never reads /tests.
set -eu

MODULE="/app/emd_distance.py"
OUT="/app/distance.json"

# ---- 1. Write the deliverable module (this IS the work, not a canned answer).
cat > "$MODULE" <<'PY'
"""Rust Quill freight-desk transport distance.

The squared transport cost is the dot product of plan P and cost C; the
actual metric distance is the square root of that scalar after clamping to
non-negative.
"""
import argparse
import json
import math
import sys


def _validate(plan, cost):
    if len(plan) != len(cost):
        raise ValueError("plan and cost must have the same number of rows")
    for prow, crow in zip(plan, cost):
        if len(prow) != len(crow):
            raise ValueError("plan and cost rows must have equal length")


def sqrt_wasserstein(plan, cost):
    """Rooted transport distance: sqrt(max(0, sum_ij P[i][j]*C[i][j]))."""
    _validate(plan, cost)
    s = 0.0
    for prow, crow in zip(plan, cost):
        for p, c in zip(prow, crow):
            s += p * c
    return math.sqrt(max(0.0, s))


def main(argv=None):
    ap = argparse.ArgumentParser(description="sqrt-Wasserstein transport distance")
    ap.add_argument("--plan", required=True, help="plan JSON (2-D array)")
    ap.add_argument("--cost", required=True, help="cost JSON (2-D array)")
    ap.add_argument("--out", required=True, help="output JSON path")
    args = ap.parse_args(argv)

    with open(args.plan, "r", encoding="utf-8") as fh:
        plan = json.load(fh)
    with open(args.cost, "r", encoding="utf-8") as fh:
        cost = json.load(fh)

    try:
        d = sqrt_wasserstein(plan, cost)
    except ValueError as exc:
        print("shape mismatch: %s" % exc, file=sys.stderr)
        return 1

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump({"distance": d}, fh, indent=2)
        fh.write("\n")
    print(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$MODULE"

# 2. Run the produced CLI on the visible fixtures to generate the output.
python3 "$MODULE" --plan /app/plan.json --cost /app/cost.json --out "$OUT"

echo "solve.sh done -> $MODULE and $OUT"
ls -l "$MODULE" "$OUT"
