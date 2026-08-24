#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json, re
tokens=[l.strip() for l in open('/app/tokens.txt') if l.strip()]
def classify(s):
    if re.fullmatch(r'AKIA[0-9A-Z]{16}', s): return 'aws_access'
    if re.fullmatch(r'[A-Za-z0-9/+=]{40}', s): return 'aws_secret'
    if re.fullmatch(r'gh[pousr]_[A-Za-z0-9_]{24,}', s): return 'github'
    return 'other'
with open('/app/answer.json','w') as f:
    json.dump([{"value": t, "type": classify(t)} for t in tokens], f, indent=2)
EOF
echo "wrote answer.json"