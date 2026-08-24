#!/bin/bash
set -euo pipefail

cat > /app/fret.py <<'EOF'
import json

d = json.load(open('/app/data.json'))
E = 1.0 - (d['tau_DA'] / d['tau_D'])
with open('/app/fret_efficiency.json', 'w') as f:
    json.dump({"E": round(E, 4)}, f)
EOF
python3 /app/fret.py