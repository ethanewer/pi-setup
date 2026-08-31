#!/usr/bin/env bash
#
# dbctl.sh -- Halden Grid metering controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/grid/compose.yaml
# (database gridstore, user meterd, port 5433) and seeds the visible scenario
# exactly once (idempotent). Deliberately NOT a deliverable; never reads
# /tests. App-role connections require the compose-file password (scram).
#
# Subcommands: up | restart | stop | start | ready
set -euo pipefail

DATA=/var/lib/gridpg
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/17/bin
PORT=5433
LOGF=/var/lib/gridpg/pg.log
SEED_FLAG=/opt/gridctl/.seeded

is_ready() {
  su postgres -c "$PGBIN/pg_isready -h 127.0.0.1 -p 5433 -q" >/dev/null 2>&1
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

# Serialize concurrent `up` invocations (entrypoint + agent/verifier phases).
# Without the lock, a second up racing a first initdb can corrupt the cluster
# or fail with 'tuple concurrently updated'.
locked_up() {
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 240 9 || true
      init_db
      start_pg
    ) 9>/var/lock/gridctl.lock
  else
    init_db
    start_pg
  fi
}

init_db() {
  if [ ! -d "$DATA" ]; then
    install -d -o postgres -g postgres "$DATA"
  fi
  if [ ! -f "$DATA/PG_VERSION" ]; then
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres --auth=trust --no-locale -E UTF8" >/dev/null
    # The metering service publishes host port 5433 (see the compose file).
    printf '\nport = 5433\n' >> "$DATA/postgresql.conf"
    # superuser stays trust on loopback; every other role must present the
    # password declared in the compose file (scram-sha-256).
    cat > "$DATA/pg_hba.conf" <<'HBA'
local all all trust
host all postgres 127.0.0.1/32 trust
host all postgres ::1/128 trust
host all all 127.0.0.1/32 scram-sha-256
host all all ::1/128 scram-sha-256
HBA
    chown postgres:postgres "$DATA/pg_hba.conf"
  fi
  start_pg
  seed_main
  touch "$SEED_FLAG"
  echo "gridctl: halden grid postgres ready (seeded)" >&2
}

seed_main() {
  # Role + database described by /app/grid/compose.yaml (idempotent).
  "$PGBIN/psql" -h 127.0.0.1 -p 5433 -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'meterd') THEN
    CREATE ROLE meterd LOGIN PASSWORD 'Kestrel-Vane-2210';
  END IF;
END $$;
SQL

  local dbexists
  dbexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5433 -U postgres -d postgres -tA \
    -c "SELECT 1 FROM pg_database WHERE datname = 'gridstore'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -h 127.0.0.1 -p 5433 -U postgres -O postgres gridstore
  fi

  local tblexists
  tblexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5433 -U postgres -d gridstore -tA \
    -c "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='meter_readings'" \
    | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  "$PGBIN/psql" -h 127.0.0.1 -p 5433 -U postgres -d gridstore -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE meter_readings (
  id           serial PRIMARY KEY,
  meter        text NOT NULL,
  kwh          numeric NOT NULL,
  reading_date date NOT NULL,
  logged_at    timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON meter_readings TO meterd;

INSERT INTO meter_readings (meter, kwh, reading_date) VALUES
  ('MTR-0117', 88.0,   '2031-03-02'),
  ('MTR-0209', 3.25,   '2031-03-01'),
  ('MTR-0417', 14.6,   '2031-03-02'),
  ('MTR-0417', 15.1,   '2031-03-03'),
  ('MTR-0209', 4,      '2031-03-02'),
  ('MTR-0333', 51.75,  '2031-03-04'),
  ('MTR-0117', 90.5,   '2031-03-04'),
  ('MTR-0417', 13.875, '2031-03-01');
SQL
}

up() {
  locked_up
}

cmd="${1:-up}"
shift || true
case "$cmd" in
  up)      up ;;
  ready)   is_ready ;;
  stop)    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m immediate stop" >/dev/null 2>&1 || true ;;
  restart) su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m immediate stop" >/dev/null 2>&1 || true; start_pg ;;
  *) echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
