#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/transform.py ]; then
  if python3 - <<'PYEOF'
import subprocess, os, shlex, tempfile
inp = "alice:25\nbob:30\ncarol:10\ndave:25\nzeta:40\nmia:15\n"
exp = "ZETA 40\nBOB 30\nALICE 25\nDAVE 25\nMIA 15\nCAROL 10\n"
r = subprocess.run(['python3','/app/transform.py'], input=inp, capture_output=True, text=True)
assert r.returncode == 0, r.stderr
assert r.stdout.rstrip('\n') == exp.rstrip('\n'), (r.stdout, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt