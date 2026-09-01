#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/capi_result.txt ]; then
  if python3 - <<'PYEOF'
import sys, importlib.util
sys.path.insert(0, '/app')
spec = importlib.util.find_spec('spam')
assert spec is not None, 'spam module not found'
spam = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spam)
val = spam.add(30, 12)
assert val == 42, val
got = open('/app/capi_result.txt').read().strip()
assert got == '42', got
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt