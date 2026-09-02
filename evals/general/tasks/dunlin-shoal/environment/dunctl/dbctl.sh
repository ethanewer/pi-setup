#!/usr/bin/env bash
#
# dbctl.sh -- Larkspur Field Station Postgres controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/deploy/compose.yaml and
# seeds the scenario exactly once (idempotent). Never reads /tests.
#
# Subcommands:
#   up      init/seed (once) and ensure the instance is running
#   ready   exit 0 when pg_isready succeeds
#   stop    fast stop
set -euo pipefail

DATA=/var/lib/dunlin-db
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
LOGF="$DATA/pg.log"
PORT=5533
SEED_FLAG=/opt/dunctl/.seeded
# provisioning helpers below use the local unix socket on the scenario port
export PGPORT="$PORT"

is_ready() {
  "$PGBIN/pg_isready" -h 127.0.0.1 -p "$PORT" -q >/dev/null 2>&1
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
    # default listen_addresses: loopback TCP (md5 for clients) + unix socket
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -o '-p $PORT' -l '$LOGF' -w start" \
      >/dev/null 2>&1 || true
  fi
  wait_ready
}

# TCP connections require the real password (auth-host=md5): the agent's
# program must derive user/password from the compose file to connect at all.
# Local socket access is trust so the infrastructure can provision.
init_db() {
  if [ ! -f "$DATA/PG_VERSION" ]; then
    install -d -o postgres -g postgres "$DATA"
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres \
      --auth-local=trust --auth-host=md5 --no-locale -E UTF8" >/dev/null
  fi
}

seed_main() {
  # Idempotent provisioning: guarded creates, rows inserted only if empty.
  su postgres -c "$PGBIN/psql -d postgres -v ON_ERROR_STOP=1 -q" <<'SQL'
ALTER USER postgres PASSWORD 'Supt-Dunlin-9931';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fieldbot') THEN
    CREATE ROLE fieldbot LOGIN PASSWORD 'Kestrel-Run-4417';
  END IF;
END $$;
SQL
  local dbexists
  dbexists=$(su postgres -c "$PGBIN/psql -d postgres -tA \
    -c \"SELECT 1 FROM pg_database WHERE datname = 'fieldlog'\"" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    su postgres -c "$PGBIN/createdb -O fieldbot fieldlog"
  fi
  su postgres -c "$PGBIN/psql -d fieldlog -v ON_ERROR_STOP=1 -q" <<'SQL'
CREATE TABLE IF NOT EXISTS sensor_readings (
    id        serial PRIMARY KEY,
    station   text NOT NULL,
    metric    text NOT NULL,
    value     integer NOT NULL,
    taken_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO sensor_readings (station, metric, value)
SELECT * FROM (VALUES
  ('BUOY-9',  'salinity', 31),
  ('BUOY-9',  'temp',     14),
  ('GATE-2',  'ph',        7),
  ('GATE-2',  'temp',     19),
  ('RELAY-5', 'salinity', 30),
  ('RELAY-5', 'temp',     16),
  ('SPAR-1',  'ph',        8)
) AS v(station, metric, value)
WHERE NOT EXISTS (SELECT 1 FROM sensor_readings);
GRANT SELECT ON sensor_readings TO fieldbot;
SQL
}

up() {
  init_db
  start_pg
  seed_main
  touch "$SEED_FLAG"
  echo "dbctl: larkspur postgres ready on $PORT" >&2
}

cmd="${1:-up}"
case "$cmd" in
  up)    up ;;
  ready) is_ready ;;
  stop)  su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m fast stop" >/dev/null 2>&1 || true ;;
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
