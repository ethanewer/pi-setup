#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "dot": 15.0,
  "angle_deg": 53.1301,
  "distance": 2.23607
}
EOF
echo "wrote answer.json"