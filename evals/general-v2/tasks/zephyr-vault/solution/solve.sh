#!/usr/bin/env bash
# Oracle for zephyr-vault. Authors the four deliverables into /app, then RUNS
# the real work (the spreadsheet client and the server regression check) so the
# produced resources/reports come from executing the deliverables, not from
# precomputed answers. Never reads /tests.
set -euo pipefail
cd /app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 1. Deliverables ----
install -m 0755 "$SCRIPT_DIR/app.py"           /app/app.py
install -m 0755 "$SCRIPT_DIR/server_check.py"  /app/server_check.py
install -m 0755 "$SCRIPT_DIR/sheets_client.py" /app/sheets_client.py
install -m 0644 "$SCRIPT_DIR/audit_report.md"  /app/audit_report.md

# ---- 2. Run the spreadsheet client (creates spreadsheet + worksheet, records ids) ----
python3 /app/sheets_client.py
test -f /app/sheets_result.json || { echo "oracle: missing sheets_result.json"; exit 1; }

# ---- 3. Run the server regression check (banner + payload classes + malformed) ----
python3 /app/server_check.py
test -f /app/server_report.json || { echo "oracle: missing server_report.json"; exit 1; }

echo "oracle ok"
exit 0