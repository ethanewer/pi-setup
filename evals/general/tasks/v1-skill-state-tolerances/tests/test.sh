#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
  if python3 - <<'PYEOF'
import json

ref = json.load(open('/app/reference.json'))
act = json.load(open('/app/actual.json'))
tol = json.load(open('/app/tolerance.json'))

expected = []
all_ok = True
for key in ['temp', 'pressure', 'level']:
    ok = abs(act[key] - ref[key]) <= tol[key]
    expected.append(f"{key}={'PASS' if ok else 'FAIL'}")
    all_ok = all_ok and ok
expected.append('all=' + ('PASS' if all_ok else 'FAIL'))

got = [ln.strip() for ln in open('/app/result.txt') if ln.strip()]
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt