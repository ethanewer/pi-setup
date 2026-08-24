#!/bin/bash
set -euo pipefail

cat > /app/parsedates.py <<'PYEOF'
import os, re, json

files = [f for f in os.listdir('/app/logs') if f.endswith('.log')]

def key(fn):
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})', fn)
    if not m:
        return (9999, 0, 0, fn)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), fn)

files.sort(key=key)
with open('/app/order.json', 'w') as f:
    json.dump(files, f)
PYEOF

python3 /app/parsedates.py