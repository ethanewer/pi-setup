#!/usr/bin/env bash
#
# dbctl.sh -- Larkfield Airshed Postgres controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/airshed/compose.yaml and
# seeds the scenario exactly once (idempotent). Deliberately NOT a deliverable
# and never reads /tests; it only runs the cluster and seeds data.
#
# Subcommands:
#   up      init/seed (once) and ensure the instance is running
#   restart stop then start again
#   stop    stop
#   ready   exit 0 when pg_isready succeeds
set -euo pipefail

DATA=/var/lib/airdb
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/17/bin
LOGF="$DATA/pg.log"
SEED_FLAG=/opt/airctl/.seeded
PORT=5433

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

stop_pg() {
  if is_ready; then
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m fast stop" >/dev/null 2>&1 || true
  fi
}

seed_main() {
  # Role + database described by the compose file, then the scenario rows.
  su postgres -c "$PGBIN/psql -p $PORT -d postgres -v ON_ERROR_STOP=1 -q -f /opt/airctl/seed.sql"
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
    # TCP (loopback) connections require SCRAM password auth so that wrong
    # credentials derived from the compose file are genuinely refused.
    sed -i -E 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+[^[:space:]]+)[[:space:]]+trust$/\1 scram-sha-256/' \
      "$DATA/pg_hba.conf"
  fi
  start_pg
  seed_main
  touch "$SEED_FLAG"
  echo "dbctl: larkfield airshed postgres ready (seeded)" >&2
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
  stop)    stop_pg ;;
  restart) stop_pg; start_pg ;;
  *)       echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
