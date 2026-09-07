#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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