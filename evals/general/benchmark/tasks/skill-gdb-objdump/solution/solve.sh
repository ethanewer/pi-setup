#!/bin/bash
set -euo pipefail

cat > /app/extract.py <<'EOF'
import subprocess

def printable_runs(data, minlen=3):
    runs, cur = [], []
    for b in data:
        if 0x20 <= b < 0x7f:
            cur.append(chr(b))
        else:
            if len(cur) >= minlen:
                runs.append(''.join(cur))
            cur = []
    if len(cur) >= minlen:
        runs.append(''.join(cur))
    return runs

secret = None

# Demonstrate the target skill: inspect the binary with objdump (data section).
subprocess.run(['objdump', '-s', '-p', '-j', '.rodata', '/app/mystery'],
               capture_output=True, text=True)

data = open('/app/mystery', 'rb').read()
for chunk in printable_runs(data):
    if 'OBJD' in chunk:
        secret = chunk
        break

assert secret, 'marker not located'
with open('/app/secret.txt', 'w') as f:
    f.write(secret)
EOF
python3 /app/extract.py