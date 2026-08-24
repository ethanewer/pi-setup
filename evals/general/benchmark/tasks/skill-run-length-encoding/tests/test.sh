#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/encoded.txt ]; then
  if python3 - <<'PYEOF'
s = open('/app/input.txt').read().strip()
out = []
i = 0
while i < len(s):
    j = i
    while j < len(s) and s[j] == s[i]:
        j += 1
    out.append(s[i] + str(j - i))
    i = j
exp = ''.join(out)
got = open('/app/encoded.txt').read()
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt