#!/bin/bash
reward=0
if [ -f /app/recovered.bin ]; then
  if python3 - <<'PYEOF'
import struct
L = 128
payload = bytes([k % 256 for k in range(L - 8)])
exp = b'BINF' + struct.pack('<I', L) + payload
got = open('/app/recovered.bin', 'rb').read()
assert got == exp, ('byte mismatch')
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt