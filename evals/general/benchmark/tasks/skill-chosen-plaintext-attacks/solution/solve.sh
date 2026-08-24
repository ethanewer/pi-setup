#!/bin/bash
set -euo pipefail

cat > /app/attack.py <<'EOF'
import subprocess

def enc(hex_pt):
    r = subprocess.run(["/app/oracle", "enc", hex_pt], capture_output=True, text=True)
    return bytes.fromhex(r.stdout.strip())

def flag_ct():
    r = subprocess.run(["/app/oracle", "flag"], capture_output=True, text=True)
    return bytes.fromhex(r.stdout.strip())

# chosen plaintext: sixteen zero bytes reveal KEY
key = enc("00" * 16)
ct = flag_ct()
flag = bytes(ct[i] ^ key[i % 16] for i in range(len(ct))).decode("ascii")
open("/app/flag.txt", "w").write(flag)
EOF

python3 /app/attack.py