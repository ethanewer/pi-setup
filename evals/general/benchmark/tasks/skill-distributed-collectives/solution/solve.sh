#!/bin/bash
set -euo pipefail
cat > /app/gossip.py <<'PY'
vals = [float(x) for x in open('/app/processes.txt').read().split()]
N = 4
R = 40
for _ in range(R):
    nxt = [(vals[i] + vals[(i + 1) % N]) / 2.0 for i in range(N)]
    vals = nxt
with open('/app/final.txt', 'w') as f:
    for v in vals:
        f.write(repr(v) + '\n')
PY
python3 /app/gossip.py