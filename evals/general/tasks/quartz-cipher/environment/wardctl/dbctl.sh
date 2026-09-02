#!/usr/bin/env bash
#
# dbctl.sh -- Wardhaven Postgres role controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/warehouse/compose.yaml and
# seeds the scenario exactly once (idempotent). It is deliberately NOT a
# deliverable and never reads /tests; it only runs the cluster and seeds data.
#
# Subcommands:
#   up        init/seed (once) and ensure the instance is running
#   restart   crash-stop (immediate) then start again, simulating recovery
#   stop      crash-stop
#   start     start
#   ready     exit 0 when pg_isready succeeds
set -euo pipefail

DATA=/var/lib/waldb
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
LOGF=/var/lib/waldb/pg.log
SEED_FLAG=/opt/wardctl/.seeded

is_ready() {
  su postgres -c "$PGBIN/pg_isready -h 127.0.0.1 -p 5432 -q" >/dev/null 2>&1
}

wait_ready() {
  for _ in $(seq 1 60); do
    if is_ready; then return 0; fi
    sleep 1
  done
  echo "dbctl: postgres did not become ready" >&2
  return 1
}

start_pg() {
  [ -d "$DATA" ] || return 1
  if ! is_ready; then
    chown -R postgres:postgres "$DATA" 2>/dev/null || true
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -l '$LOGF' start" >/dev/null 2>&1 || true
  fi
  wait_ready
}

stop_crash() {
  if is_ready; then
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m immediate stop" >/dev/null 2>&1 || true
  fi
}

seed_main() {
  # seed_main is fully idempotent: it only provisions objects that are missing
  # and only inserts the baseline rows into an empty table. This makes the
  # scenario robust against a re-seed racing with the container entrypoint's
  # initial bootstrap (incremental containers), so a later `up` never fails with
  # "relation/role already exists" and never duplicates the scenario rows.

  # Role + database described by the compose file (guarded for idempotency).
  "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'durable') THEN
    CREATE ROLE durable LOGIN SUPERUSER;
  END IF;
END $$;
SQL

  local dbexists
  dbexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d postgres -tA \
    -c "SELECT 1 FROM pg_database WHERE datname = 'shipping'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -h 127.0.0.1 -p 5432 -U postgres -O postgres shipping
  fi

  # Table + baseline (order-floor) rows. A CHECKPOINT forces the baseline into
  # the heap so the later committed durable batch exists ONLY in the WAL.
  local tblexists
  tblexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d shipping -tA \
    -c "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'shipments'" \
    | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    # Table already provisioned; the scenario is already seeded. Nothing to do.
    return 0
  fi

  "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d shipping -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE shipments (
  id          serial PRIMARY KEY,
  sku         text NOT NULL,
  qty         integer NOT NULL,
  destination text NOT NULL,
  batch       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON shipments TO durable;
GRANT USAGE, SELECT ON SEQUENCE shipments_id_seq TO durable;

INSERT INTO shipments (sku, qty, destination, batch) VALUES
  ('SZ-101',  6,  'Gate House',    'seed'),
  ('SZ-202',   42,  'Quay North',    'seed'),
  ('SZ-303',   17,  'Wharf 2',       'seed');
CHECKPOINT;
SQL

  # The durable batch committed AFTER the baseline checkpoint. It is carried
  # only in the WAL and must survive an immediate crash + restart untouched.
  "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d shipping -v ON_ERROR_STOP=1 -q <<'SQL'
INSERT INTO shipments (sku, qty, destination, batch) VALUES
  ('NV-511',  23, 'Aure Quay',    'wal-committed'),
  ('NV-812',   9, 'Brock Yard',   'wal-committed'),
  ('NV-174',  41, 'Tide Spur',    'wal-committed');
SQL
}

init_db() {
  if [ -f "$SEED_FLAG" ]; then
    return 0
  fi
  if [ ! -d "$DATA" ]; then
    install -d -o postgres -g postgres "$DATA"
  fi
  if [ ! -f "$DATA/PG_VERSION" ]; then
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres --auth=trust --no-locale -E UTF8" >/dev/null
  fi
  start_pg
  seed_main
  # Simulate a crash immediately after the durable commit, then recover from WAL.
  stop_crash
  start_pg
  touch "$SEED_FLAG"
  echo "dbctl: wardhaven postgres ready (seeded)" >&2
}

up() {
  init_db
  start_pg
}

cmd="${1:-up}"
shift || true

case "$cmd" in
  up)    up ;;
  ready) is_ready ;;
  stop)  stop_crash ;;
  restart) stop_crash; start_pg ;;
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0