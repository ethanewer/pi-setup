#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/similarity.json" ]; then
  if python3 - "$APP/similarity.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(d, dict) or 'cosine_similarity' not in d:
    sys.exit(1)
v = d['cosine_similarity']
if isinstance(v, bool) or not isinstance(v, (int, float)):
    sys.exit(1)
sys.exit(0)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt