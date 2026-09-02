#!/bin/bash
# Oracle for heath-signal: writes the deliverable program /app/gridder.py, then
# RUNS it on the visible fixture to produce /app/answer.json. Never reads /tests.
set -eu

GRIDDER="/app/gridder.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$GRIDDER" <<'PY'
#!/usr/bin/env python3
"""gridder.py -- bin a 2D point cloud into a normalized 2D histogram.

Usage: python3 gridder.py <points_csv> <spec_json> <output_json>
"""
import json
import sys


def load_points(path):
    pts = []
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            parts = [p.strip() for p in s.split(",")]
            if len(parts) != 2:
                raise ValueError("bad point line: %r" % line)
            pts.append((float(parts[0]), float(parts[1])))
    return pts


def bin_points(points, box, bins):
    xmin, xmax, ymin, ymax = box
    nx, ny = bins
    wx = (xmax - xmin) / nx
    wy = (ymax - ymin) / ny
    counts = [[0] * nx for _ in range(ny)]
    for x, y in points:
        if xmin <= x <= xmax and ymin <= y <= ymax:
            j = int((x - xmin) / wx)
            if j > nx - 1:
                j = nx - 1
            i = int((y - ymin) / wy)
            if i > ny - 1:
                i = ny - 1
            counts[i][j] += 1
    return counts


def main():
    pts_path, spec_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    points = load_points(pts_path)
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    box = [float(v) for v in spec["box"]]
    bins = (int(spec["bins"][0]), int(spec["bins"][1]))

    counts = bin_points(points, box, bins)
    nx, ny = bins
    m = sum(sum(row) for row in counts)
    if m > 0:
        grid = [[counts[i][j] / m for j in range(nx)] for i in range(ny)]
    else:
        grid = [[0.0] * nx for _ in range(ny)]

    answer = {
        "shape": [ny, nx],
        "grid": grid,
        "total_points": len(points),
        "in_box": m,
        "grid_sum": float(sum(sum(row) for row in grid)),
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$GRIDDER"

# 2. Run the produced program on the visible fixture to generate the answer.
python3 "$GRIDDER" /app/points.csv /app/spec.json "$OUT"

echo "solve.sh done -> $GRIDDER and $OUT"
ls -l "$GRIDDER" "$OUT"
