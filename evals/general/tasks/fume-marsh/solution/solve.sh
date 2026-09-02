#!/bin/bash
# Oracle for fume-marsh: write the fitting tool, then RUN it on the visible
# dataset to produce /app/model.pkl and /app/manifest.json. Never reads /tests.
set -eu

TOOL="/app/fit_model.py"
MODEL_OUT="/app/model.pkl"
MANIFEST_OUT="/app/manifest.json"

cat > "$TOOL" <<'PY'
import csv
import json
import sys

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression


def fail(msg):
    print("error: %s" % msg, file=sys.stderr)
    sys.exit(1)


def main():
    if len(sys.argv) != 4:
        fail("usage: fit_model.py <csv_path> <model_out> <manifest_out>")
    csv_path, model_out, manifest_out = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        with open(csv_path, newline="") as fh:
            rows = list(csv.reader(fh))
    except OSError as exc:
        fail("cannot read %s: %s" % (csv_path, exc))

    if len(rows) < 2:
        fail("csv needs a header and at least one data row")
    header = [h.strip() for h in rows[0]]
    if len(header) < 2:
        fail("csv needs at least one feature column plus the target column")
    data_rows = rows[1:]

    parsed = []
    for i, row in enumerate(data_rows, start=2):
        if len(row) != len(header):
            fail("row %d has %d fields, expected %d" % (i, len(row), len(header)))
        try:
            vals = [float(c) for c in row]
        except ValueError:
            fail("row %d contains a non-numeric or empty cell" % i)
        if any(np.isnan(v) for v in vals):
            fail("row %d contains a NaN cell" % i)
        parsed.append(vals)

    X = np.array([r[:-1] for r in parsed], dtype=float)
    y = np.array([int(r[-1]) for r in parsed], dtype=int)
    n_features = X.shape[1]

    model = LogisticRegression(max_iter=1000)
    model.fit(X, y)

    joblib.dump(model, model_out)

    manifest = {
        "n_features": int(n_features),
        "n_samples": int(X.shape[0]),
        "feature_columns": header[:-1],
        "target_column": header[-1],
        "model_class": type(model).__name__,
    }
    with open(manifest_out, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    print("fitted %s: n_features=%d n_samples=%d -> %s, %s"
          % (manifest["model_class"], n_features, X.shape[0], model_out, manifest_out))


if __name__ == "__main__":
    main()
PY

chmod +x "$TOOL"

python3 "$TOOL" /app/data/pump_readings.csv "$MODEL_OUT" "$MANIFEST_OUT"
echo "solve.sh done -> $TOOL $MODEL_OUT $MANIFEST_OUT"
ls -l "$TOOL" "$MODEL_OUT" "$MANIFEST_OUT"
