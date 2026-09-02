#!/bin/bash
set -euo pipefail
cat > /app/ids.py <<'PYEOF'
import json, re
models = json.load(open('/app/models.json'))
pattern = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
ids = []
for m in models:
    ident = m['org'] + '/' + m['name']
    assert pattern.match(ident)
    ids.append(ident)
open('/app/ids.txt', 'w').write('\n'.join(ids) + '\n')
PYEOF
python3 /app/ids.py