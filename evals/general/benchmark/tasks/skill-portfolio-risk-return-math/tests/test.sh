#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/result.txt" ]; then
  if /usr/bin/env python3 - "$APP" <<'PYEOF'
import sys, csv
app = sys.argv[1]
rows = {}
for r in csv.DictReader(open(app + '/assets.csv')):
    rows[r['asset']] = (float(r['expected_return']), float(r['stddev']))
ra, sa = rows['A']
rb, sb = rows['B']
rho, wa, wb = 0.30, 0.60, 0.40
er = wa*ra + wb*rb
vr = wa*wa*sa*sa + wb*wb*sb*sb + 2*wa*wb*rho*sa*sb
lines = open(app + '/result.txt').read().strip().split()
g = [float(x) for x in lines[:2]]
assert len(g) >= 2 and abs(g[0]-er) < 0.0006 and abs(g[1]-vr) < 0.0006, (g, er, vr)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt