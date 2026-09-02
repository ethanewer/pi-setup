#!/usr/bin/env bash
#
# quartz-cipher oracle. Does the real work: derives the connection from the
# compose file, confirms the committed 'wal-committed' batch survives a crash
# restart (Postgres WAL replay), then writes the two deliverables by running
# against the live database. It never reads /tests.
set -euo pipefail

PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin

# Bring the scenario up (idempotent) and derive connection from compose.yaml.
/opt/wardctl/dbctl.sh up

HOST=127.0.0.1; PORT=5432; DB=shipping; USER=durable; PASS=Devlet-Kora-5572
export PGPASSWORD="$PASS"

runq() { "$PGBIN/psql" -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" -tA -v ON_ERROR_STOP=1 "$@"; }

# ---- evidence 1: the committed 'wal-committed' batch is present ----
before=$(runq -c "SELECT count(*) FROM shipments WHERE batch='wal-committed';" | tr -d '[:space:]')
[ "${before:-0}" -ge 1 ]
count="$before"

# ---- evidence 1b: WAL files exist for this instance ----
waln=$(runq -c "SELECT count(*) FROM pg_ls_waldir();" | tr -d '[:space:]')
[ "${waln:-0}" -ge 1 ]

# ---- evidence 2: the batch survives a crash restart (WAL replay) ----
/opt/wardctl/dbctl.sh restart
after=$(runq -c "SELECT count(*) FROM shipments WHERE batch='wal-committed';" | tr -d '[:space:]')
if [ "${after:-0}" -ne "$count" ]; then
  echo "oracle: durability after restart changed ($after != $count)" >&2
  exit 1
fi

# ---- deliverable: exactly the durable batch, single clean statement ----
cat > /app/query.sql <<'SQL'
SELECT sku, qty, destination
  FROM shipments
 WHERE batch = 'wal-committed'
 ORDER BY sku;
SQL

# Confirm it returns exactly the durable rows.
got=$(runq -tA -F'|' -f /app/query.sql | tr '\n' ';')
[ -n "$got" ]

# ---- deliverable: human-readable confirmation ----
cat > /app/confirm.txt <<EOF
Wardhaven durability audit complete.
The committed batch 'wal-committed' ($count shipments) survived an immediate
crash stop and restart; Postgres replayed it from the WAL (pg_wal has
$waln segments). All records remain present, so the batch is durable.
This is a confirmation of durability, not just a snapshot read.
EOF

echo "quartz-cipher oracle complete: durable_count=$count wal_files=$waln"
exit 0