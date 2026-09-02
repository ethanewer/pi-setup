#!/bin/bash
set -euo pipefail

mkdir -p /app/out

openssl x509 -in /app/cert.pem -noout -subject -dates > /tmp/certinfo.txt 2>/dev/null

python3 - <<'PY'
import json, re

text = open('/tmp/certinfo.txt').read().strip()
info = {}
for line in text.splitlines():
    line = line.strip()
    if line.startswith('subject='):
        info['subject'] = line[len('subject='):].strip()
    elif line.startswith('notBefore='):
        info['not_before'] = line[len('notBefore='):].strip()
    elif line.startswith('notAfter='):
        info['not_after'] = line[len('notAfter='):].strip()

m = re.search(r'CN\s*=\s*([^/,]+)', info.get('subject', ''))
cn = m.group(1).strip() if m else None
out = {
    "subject": info.get('subject', ''),
    "cn": cn,
    "not_before": info.get('not_before', ''),
    "not_after": info.get('not_after', ''),
}
with open('/app/out/cert_info.json', 'w') as f:
    json.dump(out, f)
print(out)
PY