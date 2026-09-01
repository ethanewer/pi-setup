#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import json, re
template = open('/app/template.txt').read()
vars_ = json.load(open('/app/vars.json'))
out = re.sub(r'\{\{\s*(\w+)\s*\}\}', lambda m: str(vars_[m.group(1)]), template)
with open('/app/output.txt', 'w') as f:
    f.write(out)
print("wrote /app/output.txt")
PYEOF