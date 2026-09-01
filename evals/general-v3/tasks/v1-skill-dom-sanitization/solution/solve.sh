#!/bin/bash
set -euo pipefail
cat > /app/sanitize.py <<'PY'
import re

def sanitize(html: str) -> str:
    out = html
    # 1. Remove <script ...> ... </script> blocks (non-greedy, case-insensitive)
    out = re.sub(r'<script\b[^>]*>.*?</script>', '', out, flags=re.I | re.S)
    # 3. Neutralize javascript: prefix inside href/src attribute values
    out = re.sub(r'(?i)(\b(?:href|src)\s*=\s*["\']?)javascript:', r'\1', out)
    # 2. Strip on* event-handler attributes (name, =, and value up to ws/>/quote)
    out = re.sub(r'\s+on\w+\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)', '', out, flags=re.I)
    return out
PY
python3 - <<'PY'
import sys
sys.path.insert(0, '/app')
from sanitize import sanitize
lines = open('/app/payloads.html').read().splitlines()
with open('/app/sanitized.txt', 'w') as f:
    f.write('\n'.join(sanitize(l) for l in lines) + '\n')
PY