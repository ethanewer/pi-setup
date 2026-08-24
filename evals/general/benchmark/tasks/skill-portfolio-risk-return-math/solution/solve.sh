#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import csv
rows = {}
for r in csv.DictReader(open('/app/assets.csv')):
    rows[r['asset']] = (float(r['expected_return']), float(r['stddev']))
ra, sa = rows['A']
rb, sb = rows['B']
rho, wa, wb = 0.30, 0.60, 0.40
er = wa*ra + wb*rb
vr = wa*wa*sa*sa + wb*wb*sb*sb + 2*wa*wb*rho*sa*sb
with open('/app/result.txt', 'w') as f:
    f.write(f'{er:.4f}\n{vr:.4f}\n')
print('E', er, 'var', vr)
PY