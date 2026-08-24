#!/bin/bash
set -euo pipefail

cat > /app/render_fen.py <<'PYEOF'
import json

with open('/app/position.fen') as f:
    fen = f.read().strip()
placement = fen.split()[0]
ranks = []
for desc in placement.split('/'):
    row = []
    for ch in desc:
        if ch.isdigit():
            row.append('.' * int(ch))
        else:
            row.append(ch)
    ranks.append(''.join(row))

from collections import Counter
material = Counter()
for r in ranks:
    for ch in r:
        if ch != '.':
            material[ch] += 1

with open('/app/board.txt', 'w') as f:
    f.write('\n'.join(ranks) + '\n')

out = {'ranks': ranks, 'material': dict(material)}
with open('/app/board.json', 'w') as f:
    json.dump(out, f, sort_keys=True)
PYEOF

python3 /app/render_fen.py