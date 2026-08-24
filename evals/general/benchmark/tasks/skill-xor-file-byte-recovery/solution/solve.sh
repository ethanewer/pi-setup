#!/bin/bash
set -euo pipefail

cat > /app/recover.py <<'EOF'
data = open("/app/data.xor", "rb").read()

def is_plaintext(b):
    # uppercase letters A-Z (65-90) and space (32)
    return b == 32 or 65 <= b <= 90

for key in range(256):
    decoded = bytes(b ^ key for b in data)
    if all(is_plaintext(c) for c in decoded):
        with open("/app/recovered.txt", "w") as f:
            f.write(decoded.decode("ascii"))
        break
EOF

python3 /app/recover.py