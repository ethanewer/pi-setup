#!/bin/bash
set -euo pipefail

cat > /app/driver.py <<'PYEOF'
import subprocess

p = subprocess.Popen(
    ['python3', '/app/child.py'],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
)
out, _ = p.communicate(input=b'hello world\n')
result = out.decode().strip()

with open('/app/result.txt', 'w') as f:
    f.write(result + '\n')
PYEOF

python3 /app/driver.py
echo "wrote /app/result.txt"