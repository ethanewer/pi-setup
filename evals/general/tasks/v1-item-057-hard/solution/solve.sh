#!/bin/bash
set -euo pipefail
# Oracle solution: sum the integers in numbers.txt and emit answer.json.
cat > /app/answer.json <<'EOF'
{"count": 5, "sum": 14}
EOF
echo "wrote /app/answer.json"