#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/doubles.json ]; then
  if python3 - <<'PYEOF'
import json, re
words = [w.strip() for w in open('/app/words.txt') if w.strip()]
matched = []
letters = {}
pat = re.compile(r'(\w)\1')
for w in words:
    m = pat.search(w)
    if m:
        matched.append(w)
        letters[w] = m.group(1)
exp = {'matched': matched, 'letters': letters}
got = json.load(open('/app/doubles.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt