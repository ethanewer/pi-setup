#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/results_out.txt ]; then
  if python3 - <<'PYEOF'
from datetime import date, timedelta
expected = []
with open('/app/dates.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        d, n = line.split()
        y, m, dd = map(int, d.split('-'))
        expected.append((date(y, m, dd) + timedelta(days=int(n))).isoformat())
got = [l.strip() for l in open('/app/results_out.txt') if l.strip()]
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt