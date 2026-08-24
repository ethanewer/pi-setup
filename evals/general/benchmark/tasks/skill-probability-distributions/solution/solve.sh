#!/bin/bash
set -euo pipefail

cat > /app/ndist.py <<'PYEOF'
import math
import json

mu, sigma, x = 50.0, 12.0, 44.0
p = 0.5 * (1.0 + math.erf((x - mu) / (sigma * math.sqrt(2.0))))

with open('/app/result.json', 'w') as f:
    json.dump({'p': p}, f)
PYEOF

python3 /app/ndist.py
echo "wrote /app/result.json"