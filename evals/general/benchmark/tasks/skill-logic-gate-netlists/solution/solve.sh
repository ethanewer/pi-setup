#!/bin/bash
set -euo pipefail
cat > /app/wires.json <<'EOF'
{
  "A": 1,
  "B": 0,
  "C": 0,
  "D": 1,
  "E": 1,
  "F": 1
}
EOF
echo "wrote wires.json"