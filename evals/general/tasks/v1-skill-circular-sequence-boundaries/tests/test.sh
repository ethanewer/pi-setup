#!/bin/bash
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