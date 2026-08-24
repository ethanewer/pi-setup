#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import math
init = [10, 20, 30, 40]
mean = sum(init) / len(init)
lines = [l.strip() for l in open('/app/final.txt') if l.strip()]
assert len(lines) == 4, lines
vals = [float(x) for x in lines]
assert all(abs(v - mean) <= 1e-3 for v in vals), (vals, mean)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt