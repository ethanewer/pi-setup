#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/decoded.txt ]; then
  if python3 - <<'PYEOF'
data = open('/app/packed.bin','rb').read()
bits = []
for byte in data:
    for sh in range(7,-1,-1):
        bits.append((byte >> sh) & 1)
exp = []
i = 0
while i + 3 <= len(bits):
    exp.append((bits[i] << 2) | (bits[i+1] << 1) | bits[i+2])
    i += 3
got = [int(x) for x in open('/app/decoded.txt').read().split()]
assert got == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt