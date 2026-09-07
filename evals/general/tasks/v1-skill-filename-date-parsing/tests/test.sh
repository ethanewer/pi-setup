#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import os, re, json
files = [f for f in os.listdir('/app/logs') if f.endswith('.log')]
def key(fn):
    m = re.search(r'(\d{4})-(\d{2})-(\d{2})', fn)
    if not m:
        return (9999, 0, 0, fn)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)), fn)
expected = sorted(files, key=key)
got = json.load(open('/app/order.json'))
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt