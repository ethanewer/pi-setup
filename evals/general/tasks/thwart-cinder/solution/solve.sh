#!/usr/bin/env bash
# Oracle for thwart-cinder: installs the real solver deliverables under /app.
# The verifier then boots the warehouse with /app/db/start.sh, drives the
# migration cycle, checks the hidden EXPLAIN access methods and the
# execution-time gate. This script never reads /tests.
set -eu

mkdir -p /app/db/migrate /app/queries
cp /solution/solver/start.sh /app/db/start.sh
chmod +x /app/db/start.sh
cp /solution/solver/forward.sql /app/db/migrate/forward.sql
cp /solution/solver/backward.sql /app/db/migrate/backward.sql
cp /solution/solver/report.sql /app/queries/report.sql

echo "oracle: deliverables installed under /app"