#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/prog.py ]; then
  printf 'alpha\nbeta\n' > /app/demo.txt
  if python3 - <<'PYEOF'
import subprocess, sys
def run(args):
    return subprocess.run(['python3','/app/prog.py']+args, capture_output=True, text=True)
r = run(['--version'])
if r.returncode != 0 or r.stdout.strip() != 'myapp version 2.3.0':
    sys.exit('version failed')
r = run(['--help'])
if 'Usage: prog [--name NAME] FILE' not in r.stdout:
    sys.exit('help failed')
r = run(['--name','ZED','/app/demo.txt'])
if r.stdout != 'ZED> alpha\nZED> beta\n':
    sys.exit('named output failed')
r = run(['/app/demo.txt'])
if r.stdout != 'alpha\nbeta\n':
    sys.exit('plain output failed')
r = run(['--bogus','/app/demo.txt'])
if r.returncode == 0 or r.stderr.strip() == '':
    sys.exit('unknown-flag not rejected')
sys.exit(0)
PYEOF
then
    reward=1
  fi
  rm -f /app/demo.txt
fi
echo "$reward" > /logs/verifier/reward.txt