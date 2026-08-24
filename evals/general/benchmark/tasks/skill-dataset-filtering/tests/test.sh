#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/dataset.json" ] && [ -f "$APP/filtered.json" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
data = json.load(open(base + '/dataset.json'))
exp = [r for r in data if r['in_stock'] is True and r['price'] <= 50.0 and r['category'] != 'food']
got = json.load(open(base + '/filtered.json'))
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt