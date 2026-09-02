#!/bin/bash
# Real oracle for basalt-fjord: write the emd.py module, then RUN it as a CLI on
# the visible fixture to produce /app/distance.json. Never reads /tests.
set -eu

MODULE="/app/emd.py"
OUT="/app/distance.json"

# ---- 1. Write the deliverable module (this IS the work, not a canned answer).
cat > "$MODULE" <<'PY'
"""Rooted transport distance: d = sqrt(max(0, sum_ij plan[i][j]*cost[i][j]))."""
import json
import math
import sys


def _as_matrix(x):
    if not isinstance(x, list) or not x:
        raise ValueError("matrix must be a non-empty list of rows")
    out = []
    width = None
    for row in x:
        if not isinstance(row, list) or not row:
            raise ValueError("each matrix row must be a non-empty list")
        if width is None:
            width = len(row)
        elif len(row) != width:
            raise ValueError("ragged matrix rows")
        vals = []
        for v in row:
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                raise ValueError("matrix cells must be numbers")
            vals.append(float(v))
        out.append(vals)
    return out


def distance(plan, cost):
    """Return the rooted metric distance sqrt(max(0, sum P*C)).

    Raises ValueError when shapes differ or inputs are not 2-D numeric arrays.
    """
    P = _as_matrix(plan)
    C = _as_matrix(cost)
    if len(P) != len(C) or len(P[0]) != len(C[0]):
        raise ValueError(
            "shape mismatch: plan is %dx%d, cost is %dx%d"
            % (len(P), len(P[0]), len(C), len(C[0]))
        )
    s = 0.0
    for prow, crow in zip(P, C):
        for p, c in zip(prow, crow):
            s += p * c
    if s < 0.0:
        s = 0.0
    return math.sqrt(s)


def main(argv):
    if len(argv) != 3:
        print("usage: python3 emd.py <input_json> <output_json>", file=sys.stderr)
        return 2
    in_path, out_path = argv[1], argv[2]
    try:
        with open(in_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict) or "plan" not in data or "cost" not in data:
            raise ValueError("input must be a JSON object with 'plan' and 'cost'")
        d = distance(data["plan"], data["cost"])
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"distance": d}, fh)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$MODULE"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$MODULE" /app/shipment.json "$OUT"

echo "solve.sh done -> $MODULE and $OUT"
ls -l "$MODULE" "$OUT"