#!/bin/bash
set -euo pipefail

cat > /app/rewrite.py <<'EOF'
def fmt(n, base):
    if n == 0:
        return '0'
    digits = '0123456789abcdef'
    out = []
    while n > 0:
        out.append(digits[n % base])
        n //= base
    return ''.join(reversed(out))

out = []
with open('/app/numbers.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        value, from_base, to_base = line.split()
        n = int(value, int(from_base))
        out.append(fmt(n, int(to_base)))

with open('/app/converted.txt', 'w') as f:
    f.write('\n'.join(out) + '\n')
EOF

python3 /app/rewrite.py