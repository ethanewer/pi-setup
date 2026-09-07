#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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