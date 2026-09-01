#!/bin/bash

mkdir -p /logs/verifier

reward=0

run_checks() {
python3 - <<'PY'
import json, re, sys, os

# 0) dependency build must have happened: compiled units + final binary exist.
for name in ("/app/train", "/app/tiny_proto.o", "/app/tiny_blas.o", "/app/imgproc.o"):
    if not os.path.isfile(name):
        sys.exit(1)

text = open("/app/run/train.log").read()
lines = text.splitlines()

# 1) header records the CUDA-free CPU build
if not lines or "CUDA" not in lines[0]:
    sys.exit(1)

# 2) exactly max_iter Iteration rows, numbered 1..max_iter ascending
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

# 3) loss decreased overall (last strictly < first)
if not (rows[-1][1] < rows[0][1]):
    sys.exit(1)

# 4) trailer confirms exact max_iter stop
if not re.search(r"SOLVER_ENDED_MAX_ITER\s+%d" % max_iter, text):
    sys.exit(1)

# 5) report.json matches log
rep = json.load(open("/app/run/report.json"))
if rep["max_iter"] != max_iter:
    sys.exit(1)
if rep["iters"] != len(rows):
    sys.exit(1)
if abs(rep["first_loss"] - round(rows[0][1], 6)) > 1e-6:
    sys.exit(1)
if abs(rep["last_loss"] - round(rows[-1][1], 6)) > 1e-6:
    sys.exit(1)
if rep["cpu"] is not True:
    sys.exit(1)

sys.exit(0)
PY
}

if [ -f /app/run/train.log ] && [ -f /app/run/report.json ]; then
  if run_checks; then
    reward=1
  else
    reward=0.3
  fi
fi

echo "$reward" > /logs/verifier/reward.txt