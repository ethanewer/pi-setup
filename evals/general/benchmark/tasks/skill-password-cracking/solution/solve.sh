#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import hashlib
target = open('/app/hash.txt').read().strip().lower()
words = [w.strip() for w in open('/app/wordlist.txt') if w.strip()]
found = None
for w in words:
    if hashlib.md5(w.encode()).hexdigest().lower() == target:
        found = w
        break
if found is None:
    raise SystemExit('password not found in wordlist')
open('/app/password.txt', 'w').write(found + '\n')
print("wrote /app/password.txt =", found)
PYEOF