#!/bin/bash
mkdir -p /logs/verifier
reward=0
python3 - <<'EOF' > /tmp/expected_valid.txt
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
if out:
    print('\n'.join(out))
EOF
exp=$(cat /tmp/expected_valid.txt 2>/dev/null)
if [ -f /app/valid_ip.txt ]; then
  got=$(python3 -c "
import sys
s=open('/app/valid_ip.txt').read().strip().splitlines()
print('\n'.join(s))
" 2>/dev/null)
  if [ "$got" = "$exp" ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt