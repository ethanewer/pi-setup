#!/bin/bash
# Oracle for iris-quarry: author the batch inference program per the contract,
# then RUN it on the visible fixtures to produce /app/predictions.json.
# Never reads /tests.
set -eu

cat > /app/classify.py <<'PY'
import json
import math
import sys


def parse_network(path):
    lines = [l for l in open(path, "r", encoding="utf-8").read().splitlines()
             if l.strip()]
    head = lines[0].split()
    if len(head) != 4 or head[0] != "ARCH":
        raise ValueError("bad ARCH header")
    D, R, C = int(head[1]), int(head[2]), int(head[3])
    nums = [float(t) for t in " ".join(lines[1:]).split()]
    need = R * D + R + C * R + C
    if len(nums) != need:
        raise ValueError("expected %d weights, found %d" % (need, len(nums)))
    it = iter(nums)
    W1 = [[next(it) for _ in range(D)] for _ in range(R)]
    B1 = [next(it) for _ in range(R)]
    W2 = [[next(it) for _ in range(R)] for _ in range(C)]
    B2 = [next(it) for _ in range(C)]
    return D, R, C, W1, B1, W2, B2


def parse_samples(path):
    xs = []
    for line in open(path, "r", encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        xs.append([float(t) for t in line.split()])
    return xs


def forward(net, x):
    D, R, C, W1, B1, W2, B2 = net
    h = [math.tanh(sum(W1[i][j] * x[j] for j in range(D)) + B1[i])
         for i in range(R)]
    logits = [sum(W2[c][i] * h[i] for i in range(R)) + B2[c] for c in range(C)]
    m = max(logits)
    exps = [math.exp(v - m) for v in logits]
    s = sum(exps)
    probs = [e / s for e in exps]
    label = 0
    for c in range(1, C):
        if logits[c] > logits[label]:
            label = c
    return label, probs


def main():
    net_path, samples_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    net = parse_network(net_path)
    D = net[0]
    labels, probs = [], []
    for x in parse_samples(samples_path):
        if len(x) != D:
            raise ValueError("sample width %d != D %d" % (len(x), D))
        l, p = forward(net, x)
        labels.append(l)
        probs.append(p)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"labels": labels, "probs": probs}, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x /app/classify.py
python3 /app/classify.py /app/network.txt /app/samples.txt /app/predictions.json

echo "solve.sh done"
ls -l /app/classify.py /app/predictions.json
