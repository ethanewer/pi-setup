#!/bin/bash
set -euo pipefail
cat > /app/schedule.json <<'EOF'
{
  "a": [{"step": 0, "start": 0}, {"step": 1, "start": 3}, {"step": 2, "start": 6}],
  "b": [{"step": 0, "start": 10}, {"step": 1, "start": 12}, {"step": 2, "start": 14}]
}
EOF
echo "wrote schedule.json"