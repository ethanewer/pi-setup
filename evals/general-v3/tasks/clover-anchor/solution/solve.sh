#!/bin/bash
# Oracle for clover-anchor: write the fit.py program (the real work), then RUN
# it on the visible fixture to produce /app/model.pkl. Never reads /tests.
set -eu

SOLVER="/app/fit.py"
OUT="/app/model.pkl"

cat > "$SOLVER" <<'PY'
import csv
import pickle
import sys


def fit(csv_path):
    feats = {}
    n = 0
    with open(csv_path, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            zone = row["zone"].strip()
            vec = [float(row["temp_c"]),
                   float(row["humidity_pct"]),
                   float(row["light_lux"])]
            feats.setdefault(zone, []).append(vec)
            n += 1
    classes = sorted(feats)
    centroids = {z: [sum(col) / len(col) for col in zip(*feats[z])]
                 for z in classes}
    return {
        "model": "nearest-centroid",
        "fitted": True,
        "n_features": 3,
        "n_samples": n,
        "classes": classes,
        "centroids": centroids,
    }


def main():
    if len(sys.argv) != 3:
        print("usage: fit.py INPUT_CSV OUTPUT_PKL", file=sys.stderr)
        return 2
    csv_path, pkl_path = sys.argv[1], sys.argv[2]
    model = fit(csv_path)
    with open(pkl_path, "wb") as fh:
        pickle.dump(model, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/data/zone_readings.csv "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
