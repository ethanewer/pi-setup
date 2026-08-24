#!/bin/bash
set -euo pipefail

cat > /app/extract.py <<'PYEOF'
import json, re

strip = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
with open('/app/log.txt', 'r', encoding='utf-8') as f:
    raw = f.read().splitlines()

lines = []
counts = {}
for ln in raw:
    clean = strip.sub('', ln).strip('\r')
    if ':' not in clean:
        continue
    level, sep, message = clean.partition(':')
    lines.append({'level': level, 'message': message})
    counts[level] = counts.get(level, 0) + 1

out = {'lines': lines, 'level_counts': counts}
import json
with open('/app/clean.json', 'w') as f:
    json.dump(out, f)
PYEOF
python3 /app/extract.py