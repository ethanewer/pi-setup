#!/bin/bash
set -eu

# Real oracle: writes the deliverable program by doing the work, then runs it
# on the provided model to produce the visible-case output. Never reads /tests.

cat > /app/infer.py <<'PY'
#!/usr/bin/env python3
"""Quantized 2-layer affine/ReLU classifier.

Usage: infer.py MODEL VECTORS OUTPUT
"""
import json
import os
import sys


def fail(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def deq(q, scale, zero):
    return scale * (q - zero)


def load(path, what):
    if not os.path.isfile(path):
        fail("missing %s file: %s" % (what, path))
    try:
        with open(path, "r") as fh:
            return json.load(fh)
    except Exception as exc:
        fail("cannot parse %s file: %r" % (what, exc))


def run(model_path, vectors_path, output_path):
    model = load(model_path, "model")
    vectors = load(vectors_path, "vectors")

    for key in ("w1", "b1", "w2", "b2", "scale", "zero"):
        if key not in model:
            fail("model is missing key %r" % key)

    try:
        scale = float(model["scale"])
        zero = float(model["zero"])
        w1 = [[float(v) for v in row] for row in model["w1"]]
        b1 = [float(v) for v in model["b1"]]
        w2 = [[float(v) for v in row] for row in model["w2"]]
        b2 = [float(v) for v in model["b2"]]
    except Exception:
        fail("all model entries must be numeric")

    if not w1 or not b1 or not w2 or not b2:
        fail("w1/b1/w2/b2 must be non-empty")
    if not isinstance(vectors, list):
        fail("vectors file must contain a JSON array")

    R = len(w1)
    D = len(w1[0])
    if any(len(row) != D for row in w1):
        fail("w1 has ragged rows")
    if len(b1) != R:
        fail("b1 length does not match w1 rows")
    C = len(w2)
    if any(len(row) != R for row in w2):
        fail("w2 width does not match W1 rows")
    if len(b2) != C:
        fail("b2 length does not match w2 rows")

    labels = []
    for x in vectors:
        if not isinstance(x, list) or len(x) != D:
            fail("input feature dimension mismatch (need %d)" % D)
        h = []
        for i in range(R):
            acc = deq(b1[i], scale, zero)
            for j in range(D):
                acc += deq(w1[i][j], scale, zero) * x[j]
            h.append(max(0.0, acc))
        logits = []
        for c in range(C):
            acc = deq(b2[c], scale, zero)
            for i in range(R):
                acc += deq(w2[c][i], scale, zero) * h[i]
            logits.append(acc)
        best = 0
        for c in range(1, C):
            if logits[c] > logits[best]:
                best = c
        labels.append(best)

    tmp = output_path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump({"labels": labels}, fh)
    os.replace(tmp, output_path)


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: infer.py MODEL VECTORS OUTPUT\n")
        return 2
    run(argv[1], argv[2], argv[3])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x /app/infer.py

# Produce the visible-case output by actually running the deliverable.
mkdir -p /app
python3 /app/infer.py /app/model.json /app/vectors.json /app/labels.json
echo "solve.sh: wrote /app/infer.py and ran visible case -> /app/labels.json" >&2