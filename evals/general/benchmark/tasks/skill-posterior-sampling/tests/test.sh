#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/posterior.txt" ]; then
  if /usr/bin/env python3 - "$APP/posterior.txt" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path).read().strip().splitlines()
p1 = lines[0].split()
pa, pb = int(p1[0]), int(p1[1])
mean = float(lines[1].strip())
mean_exp = round(12/31, 4)
assert pa == 12 and pb == 19, (pa, pb)
assert abs(mean - mean_exp) < 0.0006, (mean, mean_exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt