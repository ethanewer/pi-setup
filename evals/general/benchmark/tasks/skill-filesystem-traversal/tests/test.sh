#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/tree.json ]; then
  if python3 - <<'PYEOF'
import os, json
root = '/app/tree'
dirs = files = total_bytes = log_files = log_bytes = 0
for base, dirnames, filenames in os.walk(root):
    dirs += len(dirnames)
    for fn in filenames:
        p = os.path.join(base, fn)
        files += 1
        size = os.path.getsize(p)
        total_bytes += size
        if fn.endswith('.log'):
            log_files += 1
            log_bytes += size
exp = {'dirs': dirs, 'files': files, 'total_bytes': total_bytes,
       'log_files': log_files, 'log_bytes': log_bytes}
got = json.load(open('/app/tree.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt