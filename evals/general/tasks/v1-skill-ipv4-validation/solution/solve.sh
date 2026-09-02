#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import ipaddress
out = []
for line in open('/app/ip_candidates.txt'):
    s = line.strip()
    if not s:
        continue
    try:
        ip = ipaddress.IPv4Address(s)
        if s == str(ip):
            out.append(s)
    except Exception:
        pass
with open('/app/valid_ip.txt','w') as f:
    if out:
        f.write('\n'.join(out) + '\n')
print("valid count:", len(out))
EOF