#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/answer.json" ]; then
  if python3 - "$APP/answer.json" <<'PY'
import json, sys, math
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
try:
    dot = float(d['dot'])
    ang = float(d['angle_deg'])
    dist = float(d['distance'])
except Exception:
    sys.exit(1)
if abs(dot - 15.0) > 1e-9:
    sys.exit(1)
if abs(ang - 53.1301) > 0.01:
    sys.exit(1)
if abs(dist - 2.23607) > 0.01:
    sys.exit(1)
sys.exit(0)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt