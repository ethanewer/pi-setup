#!/bin/bash

mkdir -p /logs/verifier

reward=0

# Validate the produced training run and report. Computes everything from the
# artifacts themselves (objective), using the solver's max_iter as ground truth.
if [ -f /app/run/train.log ] && [ -f /app/run/report.json ]; then
  python3 - <<'PY'
import json, re, sys

text = open("/app/run/train.log").read()
lines = text.splitlines()

# 1) header names the CPU (CUDA-free) build
if not lines or "CUDA" not in lines[0]:
    sys.exit(1)

# 2) iteration lines: exactly max_iter, numbered 1..max_iter ascending
solver = open("/app/model/solver.prototxt").read()
max_iter = int(re.search(r"max_iter:\s*(\d+)", solver).group(1))
rows = []
for line in lines:
    m = re.match(r"Iteration (\d+), loss = ([\d.eE+-]+)$", line)
    if m:
        rows.append((int(m.group(1)), float(m.group(2))))

if len(rows) != max_iter:
    sys.exit(1)
if [n for (n, _) in rows] != list(range(1, max_iter + 1)):
    sys.exit(1)

# 3) loss decreased over the run (final < first) and never increased overall
first, last = rows[0][1], rows[-1][1]
if not (last < first):
    sys.exit(1)
for i in range(len(rows) - 2 + 1):
    if i + 1 < len(rows) and rows[i + 1][1] > rows[i][1] + 1e-9:
        sys.exit(1)

# 4) trailer says it stopped exactly at max_iter
if not re.search(r"SOLVER_ENDED_MAX_ITER\s+%d" % max_iter, text):
    sys.exit(1)

# 5) report.json matches the log exactly enough
rep = json.load(open("/app/run/report.json"))
if rep["max_iter"] != max_iter: sys.exit(1)
if rep["iters"] != len(rows): sys.exit(1)
if abs(rep["first_loss"] - round(first, 6)) > 1e-6: sys.exit(1)
if abs(rep["last_loss"] - round(last, 6)) > 1e-6: sys.exit(1)
if not isinstance(rep["monotonic"], bool): sys.exit(1)
if rep["cpu"] is not True: sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then
    reward=1
  else
    reward=0.5
  fi
fi

echo "$reward" > /logs/verifier/reward.txt