#!/bin/bash
set -euo pipefail
# ea1=100+6*8+0=148; ea2=512+5*4+0=532; ea3=40+3*12+8=84
cat > /app/answer.json <<'EOF'
{"ea1": 148, "ea2": 532, "ea3": 84}
EOF
echo "wrote answer.json"