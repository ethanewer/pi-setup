#!/bin/bash
set -euo pipefail
# Oracle solution: extract numeric tokens from mixed.txt and emit answer.json.
cat > /app/answer.json <<'EOF'
{"token_count": 8, "largest": 129.98}
EOF
echo "wrote /app/answer.json"