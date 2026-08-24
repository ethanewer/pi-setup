#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{
  "status_200_count": 3,
  "distinct_ips_count": 4,
  "paths_sorted": ["/apache_pb.gif", "/index.html", "/submit"]
}
EOF
echo "wrote answer.json"