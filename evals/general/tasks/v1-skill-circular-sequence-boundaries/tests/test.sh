#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
d = json.load(open('/app/seq.json'))
seq = d['seq']
n = len(seq)
assert n > 0
expected = [seq[i % n] for i in d['queries']]
got = json.load(open('/app/wrapped.json'))
assert got['values'] == expected, (got['values'], expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt