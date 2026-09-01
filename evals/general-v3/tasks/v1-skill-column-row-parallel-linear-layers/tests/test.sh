#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/layers.json" ] && [ -f "$APP/shard.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, sys
base = sys.argv[1]
data = json.load(open(base + '/layers.json'))
exp = {}
for L in data['layers']:
    w = L['weights']
    tiles = L['num_tiles']
    t = L['tile_id']
    if L['kind'] == 'column-parallel':
        per = L['out_features'] // tiles
        lo, hi = t*per, (t+1)*per
        shard = [row[lo:hi] for row in w]
    else:
        per = L['in_features'] // tiles
        lo, hi = t*per, (t+1)*per
        shard = w[lo:hi]
    exp[L['name']] = {"shard": shard}
got = json.load(open(base + '/shard.json'))
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt