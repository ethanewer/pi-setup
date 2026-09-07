#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
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
d = json.load(open('/app/scene.json'))
o = d['origin']; dirv = d['direction']
class c6(float):
    def __repr__(self): return repr(round(self, 6))
exp = {'hits': []}
for idx, s in enumerate(d['spheres']):
    t = solve(o, dirv, s['center'], s['radius'])
    if t is None:
        exp['hits'].append({'index': idx, 'hit': False, 't': None, 'point': None})
    else:
        t = round(t, 6)
        p = [round(o[i]+t*dirv[i], 6) for i in range(3)]
        exp['hits'].append({'index': idx, 'hit': True, 't': t, 'point': p})
got = json.load(open('/app/result.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt