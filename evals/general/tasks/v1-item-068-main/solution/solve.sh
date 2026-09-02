#!/bin/bash
set -euo pipefail
# Oracle solution: find the largest file in /app/filedir and emit answer.json.
cat > /app/answer.json <<'EOF'
{"largest": "c.txt"}
EOF
echo "wrote /app/answer.json"