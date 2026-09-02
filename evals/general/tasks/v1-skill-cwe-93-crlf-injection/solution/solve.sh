#!/bin/bash
set -euo pipefail
cat > /app/cwe.py <<'PYEOF'
def sanitize(value: str) -> str:
    return value.replace('\r', '').replace('\n', '')

if __name__ == '__main__':
    content = open('/app/threat.txt', encoding='latin-1').read()
    open('/app/safe_cookie.txt', 'w', encoding='latin-1').write(sanitize(content))
PYEOF
python3 /app/cwe.py