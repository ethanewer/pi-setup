#!/bin/bash
set -euo pipefail

python3 -m http.server 8765 --directory /app >/tmp/httpd.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

# Give it a moment to bind
sleep 1

pip install --index-url http://127.0.0.1:8765 myprobe

python3 - <<'PYEOF'
import myprobe
out = myprobe.probe()
with open('/app/out.txt', 'w') as f:
    f.write(out + '\n')
print('installed + wrote /app/out.txt')
PYEOF