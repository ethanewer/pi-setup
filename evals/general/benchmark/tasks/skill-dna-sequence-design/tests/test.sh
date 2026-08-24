#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/designed.txt ]; then
  if python3 - <<'PY'
s = open('/app/designed.txt').read().strip().upper()
if len(s) != 10:
    raise SystemExit('len')
if any(c not in "ACGT" for c in s):
    raise SystemExit('bases')
if any(s.count(c) < 1 for c in "ACGT"):
    raise SystemExit('coverage')
if any(s[i] == s[i+1] for i in range(len(s)-1)):
    raise SystemExit('adjacent')
if s[0] != 'A':
    raise SystemExit(s)
if s[-1] != 'G':
    raise SystemExit(s)
if s.count('T') != 2:
    raise SystemExit(s)
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt