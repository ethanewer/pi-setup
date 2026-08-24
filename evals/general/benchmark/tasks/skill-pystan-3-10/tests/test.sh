#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
  if python3 - <<'PYEOF'
import re

content = open('/app/result.txt').read().strip()
m = re.search(r'b_mean=\s*(-?[0-9]+(\.[0-9]+)?)', content)
if not m:
    raise SystemExit(content)
b_mean = float(m.group(1))
if abs(b_mean - 1.7) > 0.25:
    raise SystemExit(b_mean)
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt