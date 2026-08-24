#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{"vulnerable": "yes", "issue": "untrusted user input is interpolated into html output without escaping", "fix": "html-escape encode user input before writing it into the page"}
EOF
echo "wrote answer.json"