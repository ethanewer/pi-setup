#!/bin/bash
set -euo pipefail

cat > /app/settings.json <<'EOF'
{"host": "db.internal", "port": 8080, "workers": 4}
EOF

python3 /app/server_app.py