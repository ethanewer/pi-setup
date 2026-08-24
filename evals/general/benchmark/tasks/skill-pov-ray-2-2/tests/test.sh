#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/scene.pov" ]; then
  if /usr/bin/env python3 - "$APP/scene.pov" <<'PY'
import re, sys
path = sys.argv[1]
try:
    txt = open(path).read()
except Exception:
    sys.exit(1)
t = txt.lower()
def has(kw):
    return re.search(r'\b' + re.escape(kw) + r'\b', t, re.M) is not None
incl = re.search(r'^\s*#include\b', t, re.M) is not None
ok = (incl
      and has('camera')
      and 'location' in t and 'look_at' in t
      and has('light_source')
      and has('sphere')
      and has('pigment')
      and re.search(r'color\s+rgb\s*<', t) is not None)
sys.exit(0 if ok else 1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt