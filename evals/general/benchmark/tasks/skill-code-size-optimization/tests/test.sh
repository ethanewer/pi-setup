#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/one.py ] && [ -f /app/numbers.txt ]; then
  if python3 - <<'PYEOF'
import os, subprocess, sys
size = os.path.getsize('/app/one.py')
assert size <= 75, size
expected = sum(map(int, open('/app/numbers.txt').read().strip()))
r = subprocess.run([sys.executable, '/app/one.py'], stdin=subprocess.PIPE, capture_output=True, cwd='/app')
assert r.returncode == 0, r.stdout
out = r.stdout.decode().strip().splitlines()
assert out and out[-1] == str(expected), (out, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt