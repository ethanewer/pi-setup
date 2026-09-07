#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, re
models = json.load(open('/app/models.json'))
expected = [m['org'] + '/' + m['name'] for m in models]
pattern = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
assert all(pattern.match(x) for x in expected)
got = [x for x in open('/app/ids.txt').read().splitlines() if x]
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt