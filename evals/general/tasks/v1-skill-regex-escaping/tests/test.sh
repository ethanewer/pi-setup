#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, re
data = json.load(open('/app/data.json'))
text = data['text']
tokens = data['tokens']
expected = {t: len(re.findall(re.escape(t), text)) for t in tokens}
got = json.load(open('/app/result.json'))
assert got['counts'] == expected, (got['counts'], expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt