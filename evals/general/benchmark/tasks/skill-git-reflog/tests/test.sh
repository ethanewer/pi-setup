#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/recovered.txt ]; then
  if python3 - <<'PYEOF'
import subprocess, os
os.chdir('/app/repo')
ids = []
for l in subprocess.run(['git','reflog','--all'], capture_output=True, text=True).stdout.splitlines():
    if l.split():
        ids.append(l.split()[0])
ids = sorted(set(ids))
exp = ""
for ident in ids:
    if subprocess.run(['git','cat-file','-e', f'{ident}^{{commit}}'], capture_output=True).returncode == 0:
        got = subprocess.run(['git','show', f'{ident}:secret.txt'], capture_output=True, text=True).stdout
        if got:
            exp = got
            break
with open('/app/recovered.txt', encoding='utf-8') as f:
    rec = f.read()
assert rec.strip() == exp.strip()
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt