#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/out.txt ] && [ -f /app/pipeline.py ]; then
python3 - <<'PYEOF'
import sys
try:
    ns = {}
    exec(open('/app/pipeline.py').read(), ns)
    expected = "\n".join(ns['run_sequential'](ns['ITEMS'])) + "\n"
    got = open('/app/out.txt').read()
    sys.exit(0 if got == expected else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt