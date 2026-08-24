#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/server.py ] && [ -f /app/state.txt ]; then
  if python3 - <<'PYEOF'
# Re-run the server to produce fresh state, then verify invariants.
import threading

ns = {}
src = open('/app/server.py').read()
exec(src, ns)

total_line = None
keys_line = None
for l in open('/app/state.txt'):
    l = l.strip()
    if l.startswith('total='):
        total_line = int(l.split('=')[1])
    elif l.startswith('keys='):
        keys_line = int(l.split('=')[1])

assert total_line == 800, total_line
assert keys_line == 4, keys_line
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt