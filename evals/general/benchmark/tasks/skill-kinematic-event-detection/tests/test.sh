#!/bin/bash
mkdir -p /logs/verifier
reward=0
exp=$(python3 - <<'EOF' 2>/dev/null
import csv
rows = [r for r in csv.DictReader(open('/app/motion.csv'))]
x = [float(r['x']) for r in rows]
ts = [float(r['t']) for r in rows]
prev = None
for i in range(len(x) - 1):
    v = x[i+1] - x[i]
    if prev is not None and prev > 0 and v < 0:
        print("%g" % ts[i])
        break
    if v != 0:
        prev = v
EOF
)
if [ -n "$exp" ] && [ -f /app/event.txt ]; then
  got=$(python3 -c "print(open('/app/event.txt').read().strip())" 2>/dev/null)
  if python3 -c "import sys;sys.exit(0 if abs(float(sys.argv[1])-float(sys.argv[2]))<1e-9 else 1)" "$got" "$exp" 2>/dev/null; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt