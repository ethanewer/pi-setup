#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import csv
from datetime import date
start = date(2024, 1, 1)
end = date(2024, 12, 31)
expected = []
with open('/app/records.csv', newline='') as f:
    for row in csv.DictReader(f):
        y, m, d = map(int, row['entry_date'].split('-'))
        if start <= date(y, m, d) <= end:
            expected.append(row['id'])
got = [x for x in open('/app/valid_ids.txt').read().splitlines() if x]
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt