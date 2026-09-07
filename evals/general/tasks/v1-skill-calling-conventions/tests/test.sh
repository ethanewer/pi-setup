#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/answer.json" ]; then
  if python3 - "$APP/answer.json" <<'PYEOF'
import json, sys
exp = {"func1": "cdecl", "func2": "stdcall",
       "stack_cleaner_func1": "caller", "stack_cleaner_func2": "callee"}
try:
    got = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt