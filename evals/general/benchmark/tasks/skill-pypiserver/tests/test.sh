#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import sys
try:
    import pipysample
except ImportError:
    sys.exit(1)
line = open('/app/proof.txt').read().strip()
expect = pipysample.greet("world") + ";" + str(pipysample.VALUE + 1)
assert line == expect, (line, expect)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt