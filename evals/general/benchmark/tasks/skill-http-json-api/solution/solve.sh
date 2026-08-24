#!/bin/bash
set -euo pipefail
python3 /app/server.py &
sleep 1
python3 - <<'PYEOF'
import json, urllib.request
with urllib.request.urlopen('http://127.0.0.1:8080/api/items') as r:
    data = json.load(r)
total = sum(item['price'] for item in data)
open('/app/sum.txt', 'w').write(str(total))
PYEOF
kill %1 2>/dev/null || true