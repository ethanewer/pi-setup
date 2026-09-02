#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app')
from sanitize import sanitize
lines = open('/app/payloads.html').read().splitlines()
outs = [sanitize(l) for l in lines]
joined = "\n".join(outs)
name = joined.lower()
for bad in ('<script', 'javascript:', 'onclick=', 'onerror=', 'onload='):
    assert bad not in name, (bad, joined)
# benign markup preserved
assert 'src="alert(1)"' in outs[1] or '<img src=x>' in outs[1], outs[1]
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt