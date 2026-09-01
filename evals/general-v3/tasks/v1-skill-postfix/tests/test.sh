#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/answer.json" ]; then
  if /usr/bin/env python3 - "$APP/answer.json" <<'PYEOF'
import json, re, sys
path = sys.argv[1]
exp = {
  "smtp_port": "25",
  "main_config": "/etc/postfix/main.cf",
  "local_delivery_param": "mydestination",
  "reload_command": "postfix reload",
  "queue_tool": "mailq",
}
def norm(s):
    return re.sub(r'[^a-z0-9/_\.-]', '', str(s).strip().lower())
try:
    got = json.load(open(path))
except Exception:
    sys.exit(1)
for k, v in exp.items():
    if k not in got:
        sys.exit(1)
    if norm(got[k]) != norm(v):
        sys.exit(1)
sys.exit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt