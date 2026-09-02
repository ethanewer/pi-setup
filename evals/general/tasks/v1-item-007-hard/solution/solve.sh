#!/bin/bash
set -euo pipefail

cd /app

# Multi-stage dependency build: compile proto/blas/imgproc units (stage 1),
# then link the trainer (stage 2).
make

mkdir -p /app/run

# Run, honoring solver's exact max_iter budget; log goes to solver's `log` key.
./train -solver /app/model/solver.prototxt

# Inspect the training log and emit the factual report.
python3 - <<'PY'
import json, re

text = open("/app/run/train.log").read()
rows = []
for line in text.splitlines():
    m = re.match(r"Iteration (\d+), loss = ([\d.eE+-]+)$", line)
    if m:
        rows.append((int(m.group(1)), float(m.group(2))))

solver = open("/app/model/solver.prototxt").read()
max_iter = int(re.search(r"max_iter:\s*(\d+)", solver).group(1))

report = {
    "max_iter": max_iter,
    "iters": len(rows),
    "first_loss": round(rows[0][1], 6),
    "last_loss": round(rows[-1][1], 6),
    "cpu": True,
}
with open("/app/run/report.json", "w") as f:
    json.dump(report, f)
print("report written")
PY