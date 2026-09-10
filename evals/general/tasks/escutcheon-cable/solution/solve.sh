#!/usr/bin/env bash
# Oracle for escutcheon-cable. Installs the traced cart repository from
# /solution/solved over the shipped (untraced) baseline, so that bringing the
# stack up via the deliverable produces the observability the verifier
# requires. Creates the declared deliverable /app/up.sh and the rest of the
# solved files.
set -euo pipefail
S=/solution/solved

cp -f "$S/up.sh" /app/up.sh
chmod +x /app/up.sh
cp -f "$S/README.md" /app/README.md

mkdir -p /app/services/frontend /app/services/backend /app/services/collector /app/data
cp -f "$S/services/frontend/frontend.py"  /app/services/frontend/frontend.py
cp -f "$S/services/backend/main.go"       /app/services/backend/main.go
cp -f "$S/services/backend/go.mod"        /app/services/backend/go.mod
cp -f "$S/services/collector/collector.py" /app/services/collector/collector.py
cp -f "$S/data/orders.json"               /app/data/orders.json

echo "oracle installed the traced cart repository"
