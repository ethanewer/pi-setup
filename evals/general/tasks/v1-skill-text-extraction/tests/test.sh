#!/bin/bash
# Verifier for skill-text-extraction: recompute token facts from mixed.txt.
mkdir -p /logs/verifier
reward=0

if [ -f /app/mixed.txt ] && [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json, re, sys

token_re = re.compile(r'[0-9.]+')
parsed = re.compile(r'^[0-9]+\.[0-9]+$|^[0-9]+$')

tokens = []
for m in token_re.finditer(open('/app/mixed.txt').read()):
    t = m.group(0)
    if parsed.match(t):
        tokens.append(t)

expected = {
    'token_count': len(tokens),
    'largest': max((float(t) for t in tokens), default=0.0),
}

try:
    got = json.load(open('/app/answer.json'))
except Exception:
    sys.exit(1)

if not isinstance(got, dict):
    sys.exit(1)
if {k: got.get(k) for k in expected} != expected:
    sys.exit(1)
if not (abs(got.get('largest', -1) - expected['largest']) < 1e-9):
    sys.exit(1)
print('text-extraction probe verified')
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt