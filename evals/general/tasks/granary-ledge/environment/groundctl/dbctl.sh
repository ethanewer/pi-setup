#!/usr/bin/env bash
#
# dbctl.sh -- Granary Ledge Postgres controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/deploy/stack.yml and
# seeds the scenario exactly once (idempotent). Deliberately NOT a
# deliverable; never reads /tests.
#
# Subcommands: up | ready | stop | start
set -euo pipefail

DATA=/var/lib/granarydb
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/17/bin
LOGF="$DATA/pg.log"
SEED_FLAG=/opt/groundctl/.seeded
PORT=5544

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
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -l '$LOGF' start" >/dev/null 2>&1 || true
  fi
  wait_ready
}

psql_sock() { # psql_sock DB "SQL"  -- via unix socket (trust), as postgres
  "$PGBIN/psql" -U postgres -p "$PORT" -d "$1" -tA -v ON_ERROR_STOP=1 -q -c "$2"
}

seed_main() {
  # Role + database described by the compose file (guarded for idempotency).
  psql_sock postgres "DO \$\$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'stocker') THEN
      CREATE ROLE stocker LOGIN PASSWORD 'Granary-Vest-8841';
    END IF;
  END \$\$;"

  local dbexists
  dbexists=$(psql_sock postgres "SELECT 1 FROM pg_database WHERE datname = 'provisions'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -U postgres -p "$PORT" -O stocker provisions
  fi

  local tblexists
  tblexists=$(psql_sock provisions "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='items'" | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  psql_sock provisions "CREATE TABLE items (
    sku           text PRIMARY KEY,
    name          text NOT NULL,
    stock         integer NOT NULL,
    reorder_point integer NOT NULL,
    price         numeric(10,2) NOT NULL
  );"
  psql_sock provisions "INSERT INTO items (sku, name, stock, reorder_point, price) VALUES
    ('GR-1001', 'Pearled Barley',    40, 10, 3.20),
    ('GR-1002', 'Stoneground Rye',    4, 12, 4.55),
    ('GR-1003', 'Yellow Split Peas', 25, 25, 2.10),
    ('GR-1004', 'Buckwheat Groats',   9, 15, 5.75),
    ('GR-1005', 'Millet Hulls',      60, 20, 1.95),
    ('GR-1006', 'Spelt Flakes',       2,  9, 6.40),
    ('GR-1007', 'Oat Groats',        33,  5, 2.85),
    ('GR-1008', 'Teff Grain',         0,  6, 8.10);"
  psql_sock provisions "GRANT SELECT ON items TO stocker;"
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
  # Listen on the published host port from the compose file; TCP requires the
  # compose-provided password (scram), unix socket stays trust for the role
  # script and verifier.
  {
    echo "port = $PORT"
    echo "listen_addresses = '127.0.0.1'"
  } >> "$DATA/postgresql.conf"
  sed -i 's/^\(host .*\)trust$/\1scram-sha-256/' "$DATA/pg_hba.conf"
  chown postgres:postgres "$DATA/postgresql.conf" "$DATA/pg_hba.conf"
  start_pg
  seed_main
  touch "$SEED_FLAG"
  echo "dbctl: granary ledge postgres ready (seeded)" >&2
}

cmd="${1:-up}"
case "$cmd" in
  up)    init_db; start_pg ;;
  ready) is_ready ;;
  stop)  if is_ready; then su postgres -c "$PGBIN/pg_ctl -D '$DATA' -m fast stop" >/dev/null 2>&1 || true; fi ;;
  start) start_pg ;;
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
