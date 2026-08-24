#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/version.txt ] && [ -f /app/index.html ]; then
python3 - <<'PYEOF'
import sys, re
try:
    html = open('/app/index.html', encoding='utf-8').read()
    vers = []
    for m in re.finditer(r'demo-([0-9]+(?:\.[0-9]+)*)-py3-none-any\.whl', html):
        vers.append(tuple(int(x) for x in m.group(1).split('.')))
    if not vers:
        sys.exit(1)
    expected = '.'.join(str(x) for x in max(vers))
    got = open('/app/version.txt').read().strip()
    sys.exit(0 if got == expected else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt