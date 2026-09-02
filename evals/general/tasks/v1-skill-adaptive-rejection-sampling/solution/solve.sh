#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "log_concave_required": true,
  "pw_linear_log_envelope": true,
  "unnormalized_allowed": true,
  "requires_gaussian": false
}
EOF
echo "wrote answer.json"