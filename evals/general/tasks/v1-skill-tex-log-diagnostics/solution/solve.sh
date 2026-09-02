#!/bin/bash
set -euo pipefail

mkdir -p /app/out

python3 - <<'PY'
import json, re

lines = open('/app/run.log', encoding='utf-8', errors='replace').read().splitlines()
line_no = None
msg = None
for i, ln in enumerate(lines):
    if ln.startswith('!'):
        msg = ln[1:].strip().rstrip('.')
        for j in range(i + 1, len(lines)):
            m = re.match(r'^l\.(\d+)', lines[j])
            if m:
                line_no = int(m.group(1))
                break
        break

assert line_no is not None and msg, "no error found"
with open('/app/out/error.json', 'w') as f:
    json.dump({"line": line_no, "message": msg}, f)
print(line_no, msg)
PY