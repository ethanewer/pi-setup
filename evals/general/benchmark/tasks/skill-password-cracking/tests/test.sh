#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/hash.txt ] && [ -f /app/password.txt ] && [ -f /app/wordlist.txt ]; then
python3 - <<'PYEOF'
import sys, hashlib
try:
    target = open('/app/hash.txt').read().strip().lower()
    words = [w.strip() for w in open('/app/wordlist.txt') if w.strip()]
    expected = None
    for w in words:
        if hashlib.md5(w.encode()).hexdigest().lower() == target:
            expected = w
            break
    got = open('/app/password.txt').read().strip().lower()
    sys.exit(0 if (expected is not None and got == expected.lower()) else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt