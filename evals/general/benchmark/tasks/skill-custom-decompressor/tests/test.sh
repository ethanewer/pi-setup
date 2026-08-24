#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/unpacked.txt ]; then
  if python3 - <<'PYEOF'
out = bytearray()
with open('/app/packed.dat') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        count, hx = line.split()
        out.extend(bytes([int(hx, 16)]) * int(count))
with open('/app/unpacked.txt', 'rb') as f:
    got = f.read()
assert got == bytes(out)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt