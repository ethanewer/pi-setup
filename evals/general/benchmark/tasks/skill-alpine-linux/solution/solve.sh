#!/bin/bash
set -euo pipefail
cat > /app/answer.json <<'EOF'
{"package_manager": "apk", "c_library": "musl", "repositories_file": "/etc/apk/repositories", "init_system": "openrc"}
EOF
echo "wrote answer.json"