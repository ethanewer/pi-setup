#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
n = int(open('/app/n.txt').read().strip())
a, b = 0, 1
for _ in range(n):
    a, b = b, a + b
got = json.load(open('/app/fib.json'))
assert got.get('n') == n, got
assert got.get('value') == a, (got.get('value'), a)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt