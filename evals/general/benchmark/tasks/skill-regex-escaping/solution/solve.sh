#!/usr/bin/env bash
set -euo pipefail
cat > /app/esc.py <<'PYEOF'
import json, re
data = json.load(open('/app/data.json'))
text = data['text']
tokens = data['tokens']
counts = {t: len(re.findall(re.escape(t), text)) for t in tokens}
with open('/app/result.json', 'w') as f:
    json.dump({'counts': counts}, f)
PYEOF
python3 /app/esc.py