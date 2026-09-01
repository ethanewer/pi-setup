#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/ranges.json ]; then
  if python3 - <<'PYEOF'
import json
from datetime import datetime
from zoneinfo import ZoneInfo
from collections import Counter

events = json.load(open('/app/events.json'))
zones = ['America/New_York', 'Asia/Tokyo']
expected = {}
for z in zones:
    dates = []
    for t in events:
        dt = datetime.fromisoformat(t.replace('Z', '+00:00'))
        dates.append(dt.astimezone(ZoneInfo(z)).date().isoformat())
    c = sorted(Counter(dates).items())
    expected[z] = {
        'min_date': min(dates),
        'max_date': max(dates),
        'counts': [{'date': d, 'count': n} for d, n in c],
    }
got = json.load(open('/app/ranges.json'))
assert set(got.keys()) == set(expected.keys()), (got, expected)
for z in zones:
    assert set(got[z].keys()) == {'min_date', 'max_date', 'counts'}, (z, got[z])
    assert got[z]['min_date'] == expected[z]['min_date'], (z, got[z]['min_date'])
    assert got[z]['max_date'] == expected[z]['max_date'], (z, got[z]['max_date'])
    assert got[z]['counts'] == expected[z]['counts'], (z, got[z]['counts'])
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt