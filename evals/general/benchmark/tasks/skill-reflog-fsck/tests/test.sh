#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/agent.txt ]; then
  if python3 - <<'PYEOF'
import subprocess, sys
want = open('/app/agent.txt').read().strip()
if len(want) != 40:
    sys.exit(1)
res = subprocess.run(['git','cat-file','--batch-all-objects','--batch-check'],
                     cwd='/app/repo', text=True, capture_output=True)
ok = False
for line in res.stdout.splitlines():
    parts = line.split()
    if len(parts) == 3 and parts[1] == 'commit':
        sha = parts[0]
        subj = subprocess.run(['git','show','-s','--format=%s',sha], cwd='/app/repo',
                              text=True, capture_output=True).stdout.strip()
        if subj == 'golden-secret':
            ok = (want == sha)
            break
assert ok, 'no matching commit'
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt