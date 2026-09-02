#!/bin/bash
# Verifier for item-068-main: recompute largest file from /app/filedir.
mkdir -p /logs/verifier
reward=0

if [ -d /app/filedir ] && [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import sys, json, os

d = '/app/filedir'
entries = []
for name in os.listdir(d):
    p = os.path.join(d, name)
    if os.path.isfile(p):
        entries.append((os.path.getsize(p), name))

if not entries:
    sys.exit(1)

max_size = max(s for s, _ in entries)
candidates = sorted(n for s, n in entries if s == max_size)
expected = candidates[0]

try:
    got = json.load(open('/app/answer.json'))
except Exception:
    sys.exit(1)

if not isinstance(got, dict):
    sys.exit(1)
if got.get('largest') != expected:
    sys.exit(1)
print('item-068 probe verified')
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt