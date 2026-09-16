#!/usr/bin/env bash
#
# pgctl.sh -- CargoOps PostgreSQL role controller (image infrastructure).
#
# Brings up the PostgreSQL instance for the cargoops scenario and seeds the
# database exactly once (idempotent). It is deliberately NOT a deliverable.
# It never reads /tests and never writes /app; it only runs the cluster and
# loads the deterministic scenario data from /opt/cargoctl/seed_cargoops.sql.
#
# Subcommands:
#   up        init/seed (once) and ensure the instance is running
#   ready     exit 0 when pg_isready succeeds
#   stop      crash-stop
#   start     start
#   restart   crash-stop then start
set -euo pipefail

DATA=/var/lib/cargoops-pg
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
LOGF=$DATA/postgresql.log
SEED_FLAG=/opt/cargoctl/.seeded
SEED_SQL=/opt/cargoctl/seed_cargoops.sql

is_ready() {
  su postgres -c "$PGBIN/pg_isready -h 127.0.0.1 -p 5432 -q" >/dev/null 2>&1
}

wait_ready() {
  for _ in $(seq 1 90); do
    if is_ready; then return 0; fi
    sleep 1
  done
  echo "pgctl: postgres did not become ready" >&2
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

bootstrap_role_db() {
  # Role + database, guarded so a re-run is a no-op.
  "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<'SQL' || true
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ops') THEN
    CREATE ROLE ops LOGIN SUPERUSER;
  END IF;
END $$;
SQL
  local dbexists
  dbexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d postgres -tA \
    -c "SELECT 1 FROM pg_database WHERE datname = 'cargoops'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -h 127.0.0.1 -p 5432 -U postgres -O ops cargoops
  fi
}

seed() {
  if [ -f "$SEED_FLAG" ]; then
    return 0
  fi
  local tblexists
  tblexists=$("$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d cargoops -tA \
    -c "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'positions'" 2>/dev/null \
    | tr -d '[:space:]')
  if [ "${tblexists:-0}" = "1" ]; then
    # An instance already carrying scenario tables: treat it as seeded.
    touch "$SEED_FLAG"
    return 0
  fi
  "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d cargoops -v ON_ERROR_STOP=1 -q -f "$SEED_SQL"
  touch "$SEED_FLAG"
  echo "pgctl: cargoops seeded" >&2
}

init_db() {
  if [ ! -d "$DATA" ]; then
    install -d -o postgres -g postgres "$DATA"
  fi
  if [ ! -f "$DATA/PG_VERSION" ]; then
    su postgres -c "$PGBIN/initdb -D '$DATA' -U postgres --auth=trust --no-locale -E UTF8" >/dev/null
  fi
  start_pg
  bootstrap_role_db
  seed
}

up() {
  init_db
  start_pg
}

cmd="${1:-up}"
shift || true

case "$cmd" in
  up)      up ;;
  ready)   is_ready ;;
  stop)    stop_crash ;;
  start)   start_pg ;;
  restart) stop_crash; start_pg ;;
  *)       echo "unknown pgctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0