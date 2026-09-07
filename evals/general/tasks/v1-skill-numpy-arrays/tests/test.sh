#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/stats.json ]; then
  if python3 - <<'PYEOF'
import json, sys
import numpy as np

arr = np.loadtxt('/app/scores.txt', dtype=int)
mask10 = arr > 10
exp = {
    'count_gt15': int((arr > 15).sum()),
    'idx_div3': np.where(arr % 3 == 0)[0].tolist(),
    'mean_gt10': round(float(arr[mask10].mean()) if mask10.any() else 0.0, 2),
    'max_val': int(arr.max()),
}
got = json.load(open('/app/stats.json'))
ok = (set(got) == set(exp)
      and got['count_gt15'] == exp['count_gt15']
      and got['idx_div3'] == exp['idx_div3']
      and abs(got['mean_gt10'] - exp['mean_gt10']) < 0.005
      and got['max_val'] == exp['max_val'])
sys.exit(0 if ok else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
