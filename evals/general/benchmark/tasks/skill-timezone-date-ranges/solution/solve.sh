#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'PYEOF'
import json
from datetime import datetime
from zoneinfo import ZoneInfo
from collections import Counter

events = json.load(open('/app/events.json'))
zones = ['America/New_York', 'Asia/Tokyo']
out = {}
for z in zones:
    # Parsing events from IsoFormat then:
    dates = []
    # Note events are JSON strings
    for t in events:
        dt = datetime.fromisoformat(t.replace('Z', '+00:00'))
        local = dt.astimezone(ZoneInfo(z))
        dates.append(local.date().isoformat())
    c = sorted(Counter(dates).items())
    out[z] = {
        'min_date': min(dates),
        'max_date': max(dates),
        'counts': [{'date': d, 'count': n} for d, n in c],
    }
json.dump(out, open('/app/ranges.json', 'w'))
PYEOF
python3 /app/analyze.py