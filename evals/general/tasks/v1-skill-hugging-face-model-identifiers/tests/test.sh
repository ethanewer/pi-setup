#!/bin/bash
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