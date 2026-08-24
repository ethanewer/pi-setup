#!/bin/bash
set -euo pipefail
cat > /app/formats.json <<'EOF'
{"/app/arc_a.tar": "tar", "/app/arc_b.zip": "zip", "/app/arc_c.gz": "gz"}
EOF
echo "wrote formats.json"