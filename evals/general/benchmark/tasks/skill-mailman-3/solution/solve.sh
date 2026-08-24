#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "route": "A,C,B,D",
  "total_distance": 13
}
EOF
echo "wrote answer.json"