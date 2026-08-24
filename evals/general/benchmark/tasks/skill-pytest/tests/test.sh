#!/bin/bash
mkdir -p /logs/verifier
reward=0

check() {
  # 1. pytest run from /app passes with at least one passed test
  cd /app
  out=$(python3 -m pytest test_calc.py -q 2>&1)
  rc=$?
  [ $rc -ne 0 ] && return 1
  echo "$out" | grep -Eq "[1-9][0-9]* passed" || return 1

  # 2. divide must be true division
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app')
import calc
assert calc.divide(7, 2) == 3.5, calc.divide(7, 2)
PYEOF
  [ $? -ne 0 ] && return 1

  # 3. test file must actually exercise divide
  grep -q "calc.divide" /app/test_calc.py || return 1
  return 0
}

if [ -f /app/test_calc.py ] && [ -f /app/calc.py ]; then
  if check; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt