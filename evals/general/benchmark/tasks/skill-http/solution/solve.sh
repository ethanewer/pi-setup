#!/bin/bash
set -euo pipefail
python3 /app/server.py &
sleep 1
code=$(curl -s -o /app/http_body.txt -w '%{http_code}' http://127.0.0.1:8080/hello)
cat > /app/http.txt <<EOF
$code
$(cat /app/http_body.txt)
EOF
kill %1 2>/dev/null || true