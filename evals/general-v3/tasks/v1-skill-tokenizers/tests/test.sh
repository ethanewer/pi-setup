#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/sample.txt" ] && [ -f "$APP/tokens.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, re, sys
base = sys.argv[1]
text = open(base + '/sample.txt', encoding='utf-8').read()
tokens = re.findall(r"[A-Za-z0-9]+|[^A-Za-z0-9]", text)
exp = {"tokens": tokens, "count": len(tokens)}
got = json.load(open(base + '/tokens.json'))
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt