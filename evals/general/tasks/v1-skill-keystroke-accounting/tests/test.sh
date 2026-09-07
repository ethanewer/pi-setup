#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/keylog.json ] && [ -f /app/keylog_summary.json ]; then
  if python3 - <<'EOF'
import json, sys
d = json.load(open('/app/keylog.json'))
exp = {"total_keystrokes": sum(e['press'] for e in d['events']),
       "distinct_keys": len({e['key'] for e in d['events']})}
got = json.load(open('/app/keylog_summary.json'))
if got != exp:
    sys.exit('mismatch')
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt