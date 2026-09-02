#!/bin/bash
set -euo pipefail
cat > /app/parse_sources.py <<'PY'
import json
recs = []
cur = {}
with open('/app/debian-sources.list') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line.strip():
            if cur:
                recs.append(cur)
                cur = {}
            continue
        key, _, val = line.partition(':')
        cur[key.strip()] = val.strip()
    if cur:
        recs.append(cur)
recs.sort(key=lambda r: (int(r['Priority']), r['Name']))
out = [{"name": r['Name'], "version": r['Version']} for r in recs]
with open('/app/packages.json', 'w') as f:
    json.dump(out, f)
PY
python3 /app/parse_sources.py
