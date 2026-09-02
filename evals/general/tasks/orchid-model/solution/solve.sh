#!/bin/bash
# Real oracle for orchid-model: write the three deliverable programs, then RUN
# predict.py on the visible fixtures to produce /app/predictions.csv.
# Never reads /tests.
set -eu

cat > /app/nn.py <<'PY'
"""Integer MLP library for the Orchid sensor stack."""
import json
import os


def load_weights(weights_dir):
    with open(os.path.join(weights_dir, "edge_net.json"), "r", encoding="utf-8") as fh:
        return json.load(fh)


def forward(net, x):
    """Fixed semantics: integer-only 2-layer MLP with ReLU, argmax (lowest index on ties)."""
    W1, b1, W2, b2 = net["W1"], net["b1"], net["W2"], net["b2"]
    d = len(x)
    hidden = []
    for j in range(len(b1)):
        u = b1[j]
        row = W1[j]
        for i in range(d):
            u += row[i] * x[i]
        hidden.append(u if u > 0 else 0)
    logits = []
    for k in range(len(b2)):
        s = b2[k]
        row = W2[k]
        for j in range(len(hidden)):
            s += row[j] * hidden[j]
        logits.append(s)
    label = 0
    best = logits[0]
    for k in range(1, len(logits)):
        if logits[k] > best:
            best = logits[k]
            label = k
    return {"hidden": hidden, "logits": logits, "label": label}
PY

cat > /app/selftest.py <<'PY'
"""Self-test entry for the Orchid integer MLP.

Constructs the model, performs real forward passes against the known-answer
probes in <weights_dir>/kat.json, prints SELFTEST_OK / SELFTEST_FAIL: ...,
exits 0/1, and exposes run_selftest(weights_dir) -> bool (never raises).
No broad exception swallowing: only specific exception types are caught.
"""
import json
import os
import sys

import nn


def _check_dir(weights_dir):
    """Run all checks; return None on success or a reason string on failure."""
    net_path = os.path.join(weights_dir, "edge_net.json")
    kat_path = os.path.join(weights_dir, "kat.json")
    try:
        with open(net_path, "r", encoding="utf-8") as fh:
            net = json.load(fh)
        with open(kat_path, "r", encoding="utf-8") as fh:
            kat = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        return "cannot load weight set: %s" % exc

    try:
        W1, b1, W2, b2 = net["W1"], net["b1"], net["W2"], net["b2"]
        in_dim = net["in_dim"]
    except (KeyError, TypeError):
        return "weight set missing required keys"

    # structural consistency
    if len(W1) != len(b1):
        return "W1 rows != len(b1)"
    for row in W1:
        if not isinstance(row, list) or len(row) != in_dim:
            return "W1 row has wrong width"
    if len(W2) != len(b2):
        return "W2 rows != len(b2)"
    for row in W2:
        if not isinstance(row, list) or len(row) != len(b1):
            return "W2 row has wrong width"
    if not isinstance(kat, dict) or not isinstance(kat.get("probes"), list):
        return "kat.json missing probes list"

    # real forwards: construct the model once, then verify every probe
    for idx, probe in enumerate(kat["probes"]):
        try:
            x = list(probe["x"])
            want_logits = list(probe["logits"])
            want_label = probe["label"]
        except (KeyError, TypeError):
            return "probe %d malformed" % idx
        try:
            got = nn.forward(net, x)
        except (IndexError, TypeError, ValueError) as exc:
            return "probe %d forward failed: %s" % (idx, exc)
        if got["logits"] != want_logits:
            return "probe %d logits mismatch: got %r want %r" % (
                idx, got["logits"], want_logits)
        if got["label"] != want_label:
            return "probe %d label mismatch: got %r want %r" % (
                idx, got["label"], want_label)
    return None


def run_selftest(weights_dir="/app/weights"):
    """True iff every check passes; never raises; False on any failure."""
    try:
        reason = _check_dir(weights_dir)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        reason = "unexpected input error: %s" % exc
    return reason is None


def main(argv):
    weights_dir = argv[1] if len(argv) > 1 else "/app/weights"
    if run_selftest(weights_dir):
        print("SELFTEST_OK")
        return 0
    reason = _check_dir(weights_dir)
    print("SELFTEST_FAIL: %s" % (reason or "unknown failure"))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

cat > /app/predict.py <<'PY'
"""Batch classifier CLI: predict.py <weights_dir> <samples_csv> <out_csv>."""
import sys

import nn


def main(argv):
    if len(argv) != 4:
        print("usage: predict.py <weights_dir> <samples_csv> <out_csv>", file=sys.stderr)
        return 2
    weights_dir, samples_path, out_path = argv[1], argv[2], argv[3]
    net = nn.load_weights(weights_dir)
    with open(samples_path, "r", encoding="utf-8") as fh:
        lines = [ln.strip() for ln in fh if ln.strip()]
    rows = lines[1:]  # drop header
    out = ["label"]
    for line in rows:
        x = [int(v) for v in line.split(",")]
        out.append(str(nn.forward(net, x)["label"]))
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x /app/nn.py /app/selftest.py /app/predict.py

# Run the produced program on the visible fixtures to generate the deliverable.
python3 /app/predict.py /app/weights /app/samples.csv /app/predictions.csv

echo "solve.sh done"
ls -l /app/nn.py /app/selftest.py /app/predict.py /app/predictions.csv
