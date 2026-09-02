#!/bin/bash
#
# Search oracle for copper-stage.
# Creates the deliverable /app/solve.py by doing the actual tuning work, then
# RUNS it on the visible box to produce /app/tuning.json. It never reads /tests
# and never cats a precomputed hidden answer.
set -eu

cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Deterministic grid optimizer.

Usage:
    python3 /app/solve.py <bounds_in.json> <out.json>

Reads a box bending {"a":[lo,hi],"b":[lo,hi]} (inclusive, integers, lo<=hi),
maximizes sim.score(a,b) over every integer point, breaks ties by smallest a
then smallest b, and writes {a,b,evaluations,score}.
"""
import json
import sys

from sim import score


def scan(la, ha, lb, hb):
    """Return (best_a, best_b, best_score, evaluations)."""
    best_s = None
    best_a = best_b = None
    for a in range(la, ha + 1):
        for b in range(lb, hb + 1):
            s = score(a, b)
            better = best_s is None or s > best_s + 1e-12
            tie = best_s is not None and abs(s - best_s) <= 1e-12
            if better or (tie and (a < best_a or (a == best_a and b < best_b))):
                best_s, best_a, best_b = s, a, b
    evaluations = (ha - la + 1) * (hb - lb + 1)
    return best_a, best_b, best_s, evaluations


def parse_bounds(path):
    raw = json.load(open(path))
    if not isinstance(raw, dict):
        raise ValueError("bounds file must be a JSON object with keys 'a' and 'b'")
    if set(raw) != {"a", "b"}:
        raise ValueError("bounds must contain exactly keys 'a' and 'b'")
    box = {}
    for k in ("a", "b"):
        val = raw[k]
        if not (isinstance(val, list) and len(val) == 2):
            raise ValueError(f"{k} must be a 2-list [lo, hi]")
        lo, hi = val
        if (not isinstance(lo, int)) or (not isinstance(hi, int)) \
                or isinstance(lo, bool) or isinstance(hi, bool):
            raise ValueError(f"{k} bounds must be integers")
        if lo > hi:
            raise ValueError(f"{k}: lo > hi")
        box[k] = (lo, hi)
    return box


def main(source, target):
    box = parse_bounds(source)
    (la, ha), (lb, hb) = box["a"], box["b"]
    a, b, s, evals = scan(la, ha, lb, hb)
    result = {"a": a, "b": b, "evaluations": evals, "score": s}
    with open(target, "w") as f:
        json.dump(result, f, sort_keys=True, indent=2)
        f.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python3 /app/solve.py <bounds_in.json> <out.json>", file=sys.stderr)
        sys.exit(2)
    try:
        main(sys.argv[1], sys.argv[2])
    except Exception as exc:  # any malformed/unsupported input -> clean failure
        print(f"solve error: {exc}", file=sys.stderr)
        sys.exit(2)
PY
chmod +x /app/solve.py

# Produce the visible-case deliverable by actually running the solver.
python3 /app/solve.py /app/bounds.json /app/tuning.json

echo "oracle produced tuning.json:"
cat /app/tuning.json