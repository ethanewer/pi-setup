#!/bin/bash
set -euo pipefail

cd /app

# Build the CPU-only trainer (several C++ translation units).
make

mkdir -p /app/run

# Run honoring the solver's exact max_iter; log goes to solver's `log` key.
./train -solver /app/model/solver.prototxt

# Inspect the log and emit the required report.
python3 - <<'PY'
import json, re, math

text = open("/app/run/train.log").read()
rows = []
for line in text.splitlines():
    m = re.match(r"Iteration (\d+), loss = ([\d.eE+-]+)$", line)
    if m:
        rows.append((int(m.group(1)), float(m.group(2))))

solver = open("/app/model/solver.prototxt").read()
max_iter = int(re.search(r"max_iter:\s*(\d+)", solver).group(1))

first = rows[0][1]
last = rows[-1][1]
mono = all(rows[i][1] >= rows[i+1][1] - 1e-9 for i in range(len(rows)-1))

report = {
    "max_iter": max_iter,
    "iters": len(rows),
    "first_loss": round(first, 6),
    "last_loss": round(last, 6),
    "monotonic": bool(mono),
    "cpu": True,
}
with open("/app/run/report.json", "w") as f:
    json.dump(report, f)
print("report written")
PY