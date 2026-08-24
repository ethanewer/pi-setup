#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import struct
f = open('/app/numbers.bin', 'rb').read()
assert len(f) % 4 == 0
vals = struct.unpack('<%di' % (len(f) // 4), f)
expected = str(sum(vals))
got = open('/app/sum.txt').read().strip()
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt