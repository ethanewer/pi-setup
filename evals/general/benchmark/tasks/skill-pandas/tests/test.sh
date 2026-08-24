#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/summary.csv ] && [ -f /app/data.csv ]; then
  ok=0
python3 - <<'PYEOF'
import sys
try:
    import pandas as pd
    s = pd.read_csv('/app/data.csv').groupby('region', sort=False)['amount'].sum().sort_values(ascending=False)
    exp = [f"{i},{int(v)}" for i, v in s.items()]
    lines = [l.strip() for l in open('/app/summary.csv') if l.strip()]
    got = lines[1:] if lines and lines[0].lower().rstrip().startswith('region') else lines
    sys.exit(0 if got == exp else 1)
except Exception:
    sys.exit(1)
PYEOF
  rc=$?
  if [ $rc -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt
