#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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