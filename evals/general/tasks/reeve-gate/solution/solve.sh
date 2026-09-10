#!/bin/bash
# reeve-gate oracle: install the data-driven account-state engine as the
# deliverable, then prove it on the visible example scenario.
set -euo pipefail

mkdir -p /app
cp -f /solution/solver.sh /app/setup_accounts.sh
chmod +x /app/setup_accounts.sh
/app/setup_accounts.sh /app/scenario.example.json
echo "ORACLE OK: deliverable installed and example scenario applied"