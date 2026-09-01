#!/usr/bin/env bash
#
# dbctl.sh -- Gullhaven Tide Observatory Postgres controller (image infra).
#
# Brings up the PostgreSQL instance described by /app/stack/compose.yaml and
# seeds the scenario exactly once (idempotent). Deliberately NOT a deliverable
# and never reads /tests.
#
# The instance listens on 127.0.0.1:5544. Host (TCP) auth is scram-sha-256, so
# the compose-provided password is genuinely required; local (unix socket)
# auth is trust for the postgres OS superuser only.
#
# Subcommands:
#   up      init/seed (once) and ensure the instance is running
#   ready   exit 0 when pg_isready succeeds
set -euo pipefail

DATA=/var/lib/tidedb
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
LOGF=/var/lib/tidedb/pg.log
SEED_FLAG=/opt/tidectl/.seeded
PORT=5544

is_ready() {
  su postgres -c "$PGBIN/pg_isready -h 127.0.0.1 -p $PORT -q" >/dev/null 2>&1
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
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -l '$LOGF' -o '-p $PORT' start" >/dev/null 2>&1 || true
  fi
  wait_ready
}

seed_main() {
  # Fully idempotent: only provision missing objects, only insert rows into an
  # empty table. Robust against a re-seed racing the entrypoint bootstrap.

  # Role + database described by the compose file (guarded for idempotency).
  # password_encryption is forced to scram so the compose password matters.
  su postgres -c "$PGBIN/psql -p $PORT -d postgres -v ON_ERROR_STOP=1 -q" <<'SQL'
SET password_encryption = 'scram-sha-256';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gauge_reader') THEN
    CREATE ROLE gauge_reader LOGIN PASSWORD 'Tide-Gauge-9143';
  END IF;
END $$;
SQL

  local dbexists
  dbexists=$(su postgres -c "$PGBIN/psql -p $PORT -d postgres -tA \
    -c \"SELECT 1 FROM pg_database WHERE datname = 'tidehouse'\"" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    su postgres -c "$PGBIN/createdb -p $PORT -O gauge_reader tidehouse"
  fi

  local tblexists
  tblexists=$(su postgres -c "$PGBIN/psql -p $PORT -d tidehouse -tA \
    -c \"SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'readings'\"" \
    | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  su postgres -c "$PGBIN/psql -p $PORT -d tidehouse -v ON_ERROR_STOP=1 -q" <<'SQL'
CREATE TABLE readings (
  id        serial PRIMARY KEY,
  station   text NOT NULL,
  celsius   numeric(6,2) NOT NULL,
  taken_at  timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON readings TO gauge_reader;

INSERT INTO readings (station, celsius) VALUES
  ('gull-rock',    12.50),
  ('gull-rock',    11.00),
  ('gull-rock',    14.25),
  ('gull-rock',     9.75),
  ('heron-shoal',   8.00),
  ('heron-shoal',   8.50),
  ('heron-shoal',   9.00),
  ('smoke-point',  15.50),
  ('smoke-point',  16.00),
  ('smoke-point',  14.00),
  ('smoke-point',  17.25),
  ('smoke-point',  13.50);
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
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres --auth-local=trust --auth-host=scram-sha-256 --no-locale -E UTF8" >/dev/null
  fi
  start_pg
  seed_main
  touch "$SEED_FLAG"
  echo "dbctl: gullhaven postgres ready (seeded)" >&2
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
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
