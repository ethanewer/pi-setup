#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "array1_log_concave": true,
  "array2_log_concave": false
}
EOF
echo "wrote answer.json"