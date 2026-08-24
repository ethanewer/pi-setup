#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import re
src = open('/app/colors.txt').read()
toks = re.findall(r'#[0-9A-Fa-f]{6}', src)
expected = str(sum(int(t[1:], 16) for t in toks))
got = open('/app/answer.txt').read().strip()
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt