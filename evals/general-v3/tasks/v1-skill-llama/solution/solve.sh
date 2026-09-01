#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "uses_gqa": true,
  "uses_rope": true,
  "uses_rmsnorm": true,
  "decoder_only": true
}
EOF
echo "wrote answer.json"