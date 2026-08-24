#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/token.txt ] && [ -f /app/blob.bin ]; then
  if python3 - <<'PYEOF'
import re, sys
data = open('/app/blob.bin','rb').read()
# printable run of ASCII (0x21..0x7e)
expected = re.search(rb'[ -~]+', data).group(0).decode('latin1')
got = open('/app/token.txt').read().strip()
sys.exit(0 if got == expected else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt