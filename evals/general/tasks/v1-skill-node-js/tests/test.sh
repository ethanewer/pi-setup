#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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