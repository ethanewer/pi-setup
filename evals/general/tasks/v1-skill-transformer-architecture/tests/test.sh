#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/attention.json" ]; then
  if python3 - "$APP/attention.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if not isinstance(d, list) or len(d) != 3:
    sys.exit(1)
ok = True
for row in d:
    if not isinstance(row, list) or len(row) != 3:
        ok = False
    for x in row:
        if not isinstance(x, (int, float)):
            ok = False
sys.exit(0 if ok else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt