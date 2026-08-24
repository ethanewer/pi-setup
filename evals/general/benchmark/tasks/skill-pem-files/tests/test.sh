#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/certificate.pem ]; then
python3 - <<'PYEOF'
import sys
try:
    from cryptography.hazmat.primitives.serialization import load_pem_public_key
    data = open('/app/certificate.pem', 'rb').read()
    key = load_pem_public_key(data)
    e = key.public_numbers().e
    got = open('/app/answer.txt').read().strip()
    sys.exit(0 if got == str(e) else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt