#!/bin/bash
# Oracle for quill-anchor: write the metric module, then RUN it on the visible
# fixtures to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/movecost.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable module (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Rooted haulage distance from transport plan and cost ledgers."""
import json
import math
import sys


def _as_matrix(obj, name):
    if not isinstance(obj, list) or not obj:
        raise ValueError("%s must be a non-empty list of rows" % name)
    if not all(isinstance(row, list) and row for row in obj):
        raise ValueError("%s must be a 2-D array of non-empty rows" % name)
    width = len(obj[0])
    if any(len(row) != width for row in obj):
        raise ValueError("%s must be rectangular" % name)
    out = []
    for row in obj:
        clean = []
        for cell in row:
            if isinstance(cell, bool) or not isinstance(cell, (int, float)):
                raise ValueError("%s cells must be real numbers" % name)
            clean.append(float(cell))
        out.append(clean)
    return out


def route_distance(plan, cost):
    """Rooted transport distance: sqrt(max(0, sum_ij plan*cost))."""
    p = _as_matrix(plan, "plan")
    c = _as_matrix(cost, "cost")
    if len(p) != len(c) or len(p[0]) != len(c[0]):
        raise ValueError("plan and cost shapes differ")
    s = 0.0
    for pr, cr in zip(p, c):
        for pv, cv in zip(pr, cr):
            s += pv * cv
    return math.sqrt(max(0.0, s))


def _read_matrix(path):
    rows = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if "," in line:
                cells = [tok for tok in (t.strip() for t in line.split(","))]
            else:
                cells = line.split()
            rows.append([float(t) for t in cells if t != ""])
    if not rows or not rows[0]:
        raise ValueError("empty matrix in %s" % path)
    width = len(rows[0])
    if any(len(r) != width or not r for r in rows):
        raise ValueError("ragged or empty matrix in %s" % path)
    return rows


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: movecost.py <plan_csv> <cost_csv> <output_json>\n")
        return 1
    plan_path, cost_path, out_path = argv[1], argv[2], argv[3]
    try:
        plan = _read_matrix(plan_path)
        cost = _read_matrix(cost_path)
        d = route_distance(plan, cost)
    except (ValueError, OSError) as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 1
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"distance": d}, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/plan.csv /app/cost.csv "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
