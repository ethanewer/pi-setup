#!/usr/bin/env bash
#
# keelson-buoy oracle. Installs the real repair tool at the deliverable path
# and RUNS it against the live cargoops instance. Harmless to repeat: the
# repair is the minimal single-column UPDATE and is idempotent.
set -euo pipefail

cp /solution/solver.py /app/repair.py
chmod +x /app/repair.py

/opt/cargoctl/pgctl.sh up

python3 /app/repair.py "postgresql://ops@127.0.0.1:5432/cargoops" \
    /app/backups/cargoops_base_20241130.sql

echo "keelson-buoy oracle: cargoops repaired"