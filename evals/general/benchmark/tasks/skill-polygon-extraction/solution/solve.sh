#!/bin/bash
set -euo pipefail

python3 - <<'PY'
import re, math
svg = open('/app/shape.svg').read()
m = re.search(r'points="([^"]+)"', svg)
pts = [tuple(map(int, p.split(','))) for p in m.group(1).split()]
n = len(pts)
area = 0.5 * abs(sum(pts[i][0]*pts[(i+1) % n][1] - pts[(i+1) % n][0]*pts[i][1] for i in range(n)))
per = sum(math.hypot(pts[(i+1) % n][0]-pts[i][0], pts[(i+1) % n][1]-pts[i][1]) for i in range(n))
with open('/app/polygon.txt', 'w') as f:
    f.write('\n'.join(f'{x},{y}' for x, y in sorted(pts)) + '\n')
with open('/app/area.txt', 'w') as f:
    f.write(f'{area:.4f}\n')
with open('/app/perimeter.txt', 'w') as f:
    f.write(f'{per:.4f}\n')
print('area', area, 'per', per)
PY