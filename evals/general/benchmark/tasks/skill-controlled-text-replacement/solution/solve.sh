#!/bin/bash
set -euo pipefail

cat > /app/replace.py <<'PYEOF'
import re

with open('/app/spec.txt', newline='') as f:
    content = f.read()

def transform(line):
    if 'LOCK:ON' in line:
        return line
    return re.sub(r'\bTODO\b', 'DONE', line)

kept_newlines = False
lines = content.splitlines(True)
with open('/app/out.txt', 'w', newline='') as f:
    for ln in lines:
        f.write(transform(ln))
PYEOF

python3 /app/replace.py