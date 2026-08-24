#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/exact.bin" ]; then
  if python3 - "$APP/exact.bin" <<'PYEOF'
import sys
hexstr = "65786163742d6f757470757400ff01ff0a4142"
expected = bytes.fromhex(hexstr)
data = open(sys.argv[1], 'rb').read()
sys.exit(0 if data == expected else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt