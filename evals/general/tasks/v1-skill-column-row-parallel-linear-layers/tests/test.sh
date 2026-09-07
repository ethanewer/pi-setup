#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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