#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/input.json" ] && [ -f "$APP/out.json" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
records = json.load(open(base + '/input.json'))
idx = [(r['name'], r['score'], i) for i, r in enumerate(records)]
idx.sort(key=lambda t: (-t[1], t[2]))
exp = [t[0] for t in idx]
got = json.load(open(base + '/out.json'))
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt