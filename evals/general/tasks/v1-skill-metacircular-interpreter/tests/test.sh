#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/result.json" ]; then
  if python3 - "$APP/result.json" <<'PYEOF'
import json, sys
exp = [5, -17, 3.5]
try:
    got = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ok = isinstance(got, list) and len(got) == 3
if ok:
    ok = (got[0] == 5) and (got[1] == -17) and abs(got[2] - 3.5) < 1e-9
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt