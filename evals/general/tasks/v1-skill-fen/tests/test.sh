#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/board.txt ] && [ -f /app/board.json ]; then
  if python3 - <<'PYEOF'
import json
from collections import Counter
fen = open('/app/position.fen').read().strip()
placement = fen.split()[0]
ranks = []
for desc in placement.split('/'):
    parts = []
    for ch in desc:
        if ch.isdigit():
            parts.append('.' * int(ch))
        else:
            parts.append(ch)
    ranks.append(''.join(parts))
material = Counter()
for r in ranks:
    for ch in r:
        if ch != '.':
            material[ch] += 1
exp_txt = '\n'.join(ranks) + '\n'
got_txt = open('/app/board.txt').read()
assert got_txt == exp_txt, (got_txt, exp_txt)
got = json.load(open('/app/board.json'))
assert got['ranks'] == ranks
assert dict(got['material']) == dict(material), (got['material'], material)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt