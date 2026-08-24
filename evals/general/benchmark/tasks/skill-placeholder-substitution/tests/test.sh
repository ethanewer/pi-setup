#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/output.txt ] && [ -f /app/template.txt ] && [ -f /app/vars.json ]; then
python3 - <<'PYEOF'
import sys, json, re
try:
    template = open('/app/template.txt').read()
    var = json.load(open('/app/vars.json'))
    expected = re.sub(r'\{\{\s*(\w+)\s*\}\}', lambda m: str(var[m.group(1)]), template)
    got = open('/app/output.txt').read()
    sys.exit(0 if got == expected else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt