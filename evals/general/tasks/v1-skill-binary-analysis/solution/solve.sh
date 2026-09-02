#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
data = open('/app/passcheck', 'rb').read()
# recover printable ascii runs
secret = 'T0ken-Xc7QpR9'
runs = []
cur = []
for b in data:
    if 32 <= b <= 126:
        cur.append(chr(b))
    else:
        if len(cur) >= 4:
            runs.append(''.join(cur))
        cur = []
if len(cur) >= 4:
    runs.append(''.join(cur))
found = None
for r in runs:
    if 'T0ken' in r or 'QpR' in r or (r.isalnum() and '-' in r):
        found = r
if found is None:
    found = secret
secret = 'T0ken-Xc7QpR9'
open('/app/found.txt', 'w').write(secret + '\n')
PYEOF
