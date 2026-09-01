#!/bin/bash
# Oracle for basalt-ember: write the classify.py program (the real work), then
# RUN it on the visible fixtures to produce /app/predictions.json. Never reads /tests.
set -eu

SOLVER="/app/classify.py"
OUT="/app/predictions.json"

cat > "$SOLVER" <<'PY'
import json
import math
import sys


def forward(net, samples):
    std_cfg = net.get("standardize")
    W1, b1 = net["hidden"]["w"], net["hidden"]["b"]
    W2, b2 = net["output"]["w"], net["output"]["b"]
    labels, probs = [], []
    for x in samples:
        x = [float(v) for v in x]
        if std_cfg:
            x = [(v - m) / (s if s != 0 else 1.0)
                 for v, m, s in zip(x, std_cfg["mean"], std_cfg["std"])]
        h = [math.tanh(sum(w * v for w, v in zip(row, x)) + b)
             for row, b in zip(W1, b1)]
        logits = [sum(w * v for w, v in zip(row, h)) + b
                  for row, b in zip(W2, b2)]
        best = 0
        for i in range(1, len(logits)):
            if logits[i] > logits[best]:
                best = i
        m = max(logits)
        exps = [math.exp(v - m) for v in logits]
        tot = sum(exps)
        labels.append(best)
        probs.append([e / tot for e in exps])
    return labels, probs


def main():
    if len(sys.argv) != 4:
        print("usage: classify.py NETWORK SAMPLES OUTPUT", file=sys.stderr)
        return 2
    net_path, sample_path, out_path = sys.argv[1:4]
    with open(net_path) as fh:
        net = json.load(fh)
    with open(sample_path) as fh:
        samples = json.load(fh)
    labels, probs = forward(net, samples)
    with open(out_path, "w") as fh:
        json.dump({"labels": labels, "probs": probs}, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/network.json /app/samples.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
