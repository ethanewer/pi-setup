#!/usr/bin/env bash
set -euo pipefail

cat > /app/ray.py <<'PY'
import json, math

def solve(o, d, c, r):
    oc = [o[i]-c[i] for i in range(3)]
    b = -sum(d[i]*oc[i] for i in range(3))
    cc = sum(x*x for x in oc) - r*r
    disc = b*b - cc
    if disc < 0:
        return None
    t = b - math.sqrt(disc)
    if t <= 0:
        return None
    return t

scene = json.load(open('/app/scene.json'))
o = scene['origin']
dirv = scene['direction']
hits = []
for idx, s in enumerate(scene['spheres']):
    t = solve(o, dirv, s['center'], s['radius'])
    if t is None:
        hits.append({'index': idx, 'hit': False, 't': None, 'point': None})
    else:
        t = round(t, 6)
        p = [round(o[i]+t*dirv[i], 6) for i in range(3)]
        hits.append({'index': idx, 'hit': True, 't': t, 'point': p})

with open('/app/result.json', 'w') as f:
    json.dump({'hits': hits}, f)
PY

python3 /app/ray.py