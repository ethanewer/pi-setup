#!/usr/bin/env bash
#
# dbctl.sh -- Fernvale Observatory Postgres controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/warehouse/compose.yaml
# and seeds the visible scenario exactly once (idempotent). Deliberately NOT
# a deliverable and never reads /tests.
#
# Race safety: the container entrypoint and the agent/verifier may invoke
# this script concurrently, so every invocation serializes on an flock and
# the port setting is (re-)asserted before any server start. This makes the
# scenario deterministic no matter who invokes it first or in parallel.
#
# Connection model:
#   - superuser "postgres" is trusted on the unix socket (infra only)
#   - every TCP connection (127.0.0.1) requires SCRAM password auth, so a
#     client with a wrong host/port/user/db/password simply fails
#
# Subcommands:
#   up        init/seed (once) and ensure the instance is running
#   restart   stop then start again
#   ready     exit 0 when the server accepts connections on its port
set -euo pipefail

DATA=/var/lib/obsdb
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
LOGF="$DATA/pg.log"
SEED_FLAG=/opt/obsctl/.seeded
PORT=5433
SOCKDIR=/var/run/postgresql
LOCKF=/var/lock/obsctl.lock

sup() { # sup [psql args...]  -- run psql as superuser over the unix socket
  su postgres -c "$PGBIN/psql -h $SOCKDIR -p $PORT -U postgres -v ON_ERROR_STOP=1 -q $*"
}

is_ready() {
  su postgres -c "$PGBIN/pg_isready -h $SOCKDIR -p $PORT -q" >/dev/null 2>&1
}

wait_ready() {
  for _ in $(seq 1 90); do
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
    # 9>&- : do NOT leak the flock fd into pg_ctl/postmaster, or the lock
    # would stay held by the long-running server forever.
    if ! su postgres -c "$PGBIN/pg_ctl -D '$DATA' -l '$LOGF' start" 9>&- >/dev/null 2>&1; then
      echo "dbctl: pg_ctl start failed" >&2
      tail -10 "$LOGF" >&2 2>/dev/null || true
    fi
  fi
  wait_ready
}

stop_pg() {
  if is_ready; then
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m fast stop" 9>&- >/dev/null 2>&1 || true
  fi
}

seed_main() {
  # Fully idempotent: only provisions objects that are missing.
  sup -f - <<'SQL' >/dev/null
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'obs_ro') THEN
    CREATE ROLE obs_ro LOGIN PASSWORD 'Fernvale-Obs-2024-77';
  END IF;
END $$;
SQL

  local dbexists
  dbexists=$(su postgres -c "$PGBIN/psql -h $SOCKDIR -p $PORT -U postgres -tA -c \
    \"SELECT 1 FROM pg_database WHERE datname = 'telemetry'\"" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    su postgres -c "$PGBIN/createdb -h $SOCKDIR -p $PORT -U postgres -O obs_ro telemetry"
  fi

  local tblexists
  tblexists=$(su postgres -c "$PGBIN/psql -h $SOCKDIR -p $PORT -U postgres -d telemetry -tA -c \
    \"SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='telemetry_readings'\"" \
    | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  su postgres -c "$PGBIN/psql -h $SOCKDIR -p $PORT -U postgres -d telemetry -v ON_ERROR_STOP=1 -q" <<'SQL'
CREATE TABLE telemetry_readings (
    reading_id integer PRIMARY KEY,
    sensor_id  text NOT NULL,
    reading    integer NOT NULL,
    quality    text NOT NULL
);
INSERT INTO telemetry_readings (reading_id, sensor_id, reading, quality) VALUES
  (1, 'seq-alpha', 412, 'nominal'),
  (2, 'seq-beta',  388, 'nominal'),
  (3, 'seq-alpha', 501, 'drift'),
  (4, 'seq-gamma',  95, 'nominal');
GRANT SELECT ON telemetry_readings TO obs_ro;
SQL
}

init_db() {
  if [ ! -d "$DATA" ]; then
    install -d -o postgres -g postgres "$DATA" "$SOCKDIR"
  fi
  if [ ! -f "$DATA/PG_VERSION" ]; then
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres \
        --auth-local=trust --auth-host=scram-sha-256 --no-locale -E UTF8" 9>&- >/dev/null
  fi
  # Assert the server port on every invocation, before any start, so a
  # concurrent invocation can never start the server on the wrong port.
  if ! grep -q "^port[[:space:]]*=" "$DATA/postgresql.conf" 2>/dev/null; then
    su postgres -c "echo \"port = $PORT\" >> '$DATA/postgresql.conf'"
  fi
  start_pg
  if [ -f "$SEED_FLAG" ]; then
    return 0
  fi
  seed_main
  touch "$SEED_FLAG"
  echo "dbctl: fernvale postgres ready (seeded)" >&2
}

up() {
  # Serialize concurrent invocations (entrypoint vs agent vs verifier).
  # Bounded wait: never block longer than 300s on the lock.
  exec 9>"$LOCKF"
  flock -w 300 9 || { echo "dbctl: could not acquire lock" >&2; exit 1; }
  init_db
}

cmd="${1:-up}"
case "$cmd" in
  up)      up ;;
  ready)   is_ready ;;
  stop)    exec 9>"$LOCKF"; flock -w 300 9 || exit 1; stop_pg ;;
  restart) exec 9>"$LOCKF"; flock -w 300 9 || exit 1; stop_pg; start_pg ;;
  *) echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
