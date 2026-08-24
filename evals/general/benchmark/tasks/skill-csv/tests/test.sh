#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import csv
codes = {'sales': '01', 'engineering': '02', 'support': '03'}
with open('/app/people.csv', newline='') as f:
    r = csv.reader(f)
    header = next(r)
    data = list(r)
expected = [row + [codes.get(row[2], '00')] for row in data]
with open('/app/report.csv', newline='') as f:
    got = list(csv.reader(f))
assert got[0] == header + ['dept_code'], got[0]
assert got[1:] == expected, (got[1:], expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt