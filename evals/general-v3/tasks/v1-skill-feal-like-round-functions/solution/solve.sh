#!/bin/bash
set -euo pipefail

cat > /app/fbox.py <<'PYEOF'
import json

def rot(x):
    return ((x << 2) | (x >> 6)) & 0xFF

def fbox(r, k):
    # r and k are 4-element lists of ints 0..255
    return [rot((r[i] + k[i]) & 0xFF) for i in range(4)]

if __name__ == '__main__':
    with open('/app/vectors.json') as f:
        v = json.load(f)
    on = fbox(v['r'], v['k'])
    with open('/app/answers.json', 'w') as f:
        json.dump({'input': {'r': v['r'], 'k': v['k']}, 'output': on}, f)
PYEOF

python3 /app/fbox.py