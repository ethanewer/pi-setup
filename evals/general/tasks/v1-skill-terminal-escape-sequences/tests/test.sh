#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/clean.json ]; then
  if python3 - <<'PYEOF'
import json, re
strip = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
raw = open('/app/log.txt', encoding='utf-8').read().splitlines()
lines = []
counts = {}
for ln in raw:
    clean = strip.sub('', ln).strip('\r')
    if ':' not in clean:
        continue
    level, _, message = clean.partition(':')
    lines.append({'level': level, 'message': message})
    counts[level] = counts.get(level, 0) + 1
exp = {'lines': lines, 'level_counts': counts}
got = json.load(open('/app/clean.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt