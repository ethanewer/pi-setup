#!/bin/bash
# Oracle for gull-radar: write the general binning program, then RUN it on the
# visible fixtures to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import math
import sys


def parse_spec(path):
    box = bins = None
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if key == "box":
                a = [float(t) for t in value.split(",")]
                box = (a[0], a[1], a[2], a[3])
            elif key == "bins":
                b = [int(t) for t in value.split(",")]
                bins = (b[0], b[1])
    if box is None or bins is None:
        raise ValueError("grid spec missing box= or bins= line")
    return box, bins


def main():
    fixes_path, grid_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    (xmin, xmax, ymin, ymax), (nx, ny) = parse_spec(grid_path)
    wx = (xmax - xmin) / nx
    wy = (ymax - ymin) / ny

    counts = [[0] * nx for _ in range(ny)]
    outside = 0
    malformed = 0
    with open(fixes_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if line.strip() == "":
                continue
            parts = line.split(",")
            ok = len(parts) == 2
            if ok:
                try:
                    x = float(parts[0])
                    y = float(parts[1])
                except ValueError:
                    ok = False
            if not ok:
                malformed += 1
                continue
            if not (xmin <= x <= xmax and ymin <= y <= ymax):
                outside += 1
                continue
            col = min(int(math.floor((x - xmin) / wx)), nx - 1)
            row = min(int(math.floor((y - ymin) / wy)), ny - 1)
            counts[row][col] += 1

    binned = sum(sum(r) for r in counts)
    histogram = [[(c / binned) if binned else 0.0 for c in row] for row in counts]
    answer = {
        "box": [xmin, xmax, ymin, ymax],
        "bins": [nx, ny],
        "histogram": histogram,
        "outside": outside,
        "malformed": malformed,
        "binned": binned,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the report.
python3 "$SOLVER" /app/fixes.txt /app/grid.txt "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
