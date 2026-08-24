#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/dates.txt" ] && [ -f "$APP/rewritten.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import re, sys
base = sys.argv[1]
src = open(base + '/dates.txt').read()
pat = r'(?P<y>\d{4})-(?P<m>\d{2})-(?P<d>\d{2})'
exp = re.sub(pat, lambda m: '%s/%s/%s' % (m.group('m'), m.group('d'), m.group('y')), src)
got = open(base + '/rewritten.txt').read()
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt