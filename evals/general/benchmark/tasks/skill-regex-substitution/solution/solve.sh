#!/usr/bin/env bash
set -euo pipefail

# Oracle: create the rewrite script and run it to produce /app/result.txt.
cat > /app/rewrite.py <<'PY'
import re

rx = re.compile(r'^(\w+) (\w+) (\d{4})$')
out = []
for line in open('/app/data.txt'):
    line = line.rstrip('\n')
    if line.strip():
        out.append(re.sub(rx, r'\2 \1 born \3', line))

with open('/app/result.txt', 'w') as f:
    f.write('\n'.join(out) + '\n')
PY

python3 /app/rewrite.py
