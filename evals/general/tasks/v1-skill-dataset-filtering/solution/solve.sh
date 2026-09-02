#!/bin/bash
set -euo pipefail
cat > /app/filter.py <<'PY'
import json
with open('/app/dataset.json') as f:
    data = json.load(f)
kept = [r for r in data if r['in_stock'] is True and r['price'] <= 50.0 and r['category'] != 'food']
with open('/app/filtered.json', 'w') as f:
    json.dump(kept, f)
PY
python3 /app/filter.py
