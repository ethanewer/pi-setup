#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/hier_model.txt ]; then
  if python3 - <<'PYEOF'
import sys
vals = {}
for line in open('/app/hier_model.txt'):
    k, v = line.strip().split('=')
    vals[k] = float(v)
post_prec = vals['pi0'] + vals['piA'] + vals['piB']
expected = (vals['pi0']*vals['mu0'] + vals['piA']*vals['mA'] + vals['piB']*vals['mB']) / post_prec
try:
    got = float(open('/app/answer.txt').read().strip())
except Exception:
    sys.exit(1)
sys.exit(0 if abs(got - expected) <= 0.01 else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt