#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import subprocess, sys
def num(s):
    d = ''.join(c for c in s if c.isdigit())
    return int(d) if d else -1
try:
    a = num(open('/app/answer.txt').read())
    r = subprocess.run(['cobc', '-x', '-o', '/tmp/probe_exe', '/app/program.cob'], capture_output=True)
    if r.returncode != 0:
        sys.exit(1)
    o = subprocess.run(['/tmp/probe_exe'], capture_output=True, text=True)
    b = num(o.stdout)
    sys.exit(0 if (a == 55 and b == 55) else 1)
except Exception:
    sys.exit(1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt