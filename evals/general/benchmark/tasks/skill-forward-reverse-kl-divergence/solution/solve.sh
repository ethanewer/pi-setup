#!/bin/bash
set -euo pipefail

cat > /app/kl.py <<'EOF'
import json, math

p = json.load(open('/app/p.json'))
q = json.load(open('/app/q.json'))

def kl(a, b):
    return sum(0.0 if ai == 0 else ai * math.log(ai / bi) for ai, bi in zip(a, b))

out = {
    "kl_fwd": round(kl(p, q), 4),
    "kl_rev": round(kl(q, p), 4),
}
with open('/app/kl_divs.json', 'w') as f:
    json.dump(out, f)
EOF
python3 /app/kl.py