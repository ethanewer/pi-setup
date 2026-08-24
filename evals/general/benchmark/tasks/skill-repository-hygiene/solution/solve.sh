#!/usr/bin/env bash
set -euo pipefail
cd /app/repo
cat > .gitignore <<'EOF'
*.log
*.tmp
cache/
__pycache__/
EOF
git add -A
git commit -qm "hygiene"
git status --porcelain