#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/input.txt" ] && [ -f "$APP/output.txt" ]; then
  if python3 - "$APP" <<'PY'
import sys
base = sys.argv[1]
vals = []
for line in open(base + '/input.txt'):
    s = line.strip()
    if s:
        vals.append(int(s))
total = sum(vals)
count = len(vals)
mean = total / count
exp = "sum=%d\ncount=%d\nmean=%s\n" % (total, count, mean)
got = open(base + '/output.txt').read()
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt