#!/usr/bin/env bash
#
# dbctl.sh -- Moor Atlas Postgres controller (image infrastructure).
#
# Brings up the two PostgreSQL clusters of this scenario exactly once
# (idempotent):
#   main  : the authoritative beacon registry on the HOST port published by
#           /app/deploy/services.yml (5581), with the compose-provided
#           credentials (db moorside / user surveyor).
#   decoy : a retired registry on another port (5591) with the SAME database
#           name and credentials but an EMPTY beacons table. Only the compose
#           file tells the agent which instance is authoritative.
#
# Deliberately NOT a deliverable; never reads /tests.
#
# Subcommands: up | ready | stop | start
set -euo pipefail

DATA_MAIN=/var/lib/moordb
DATA_DECOY=/var/lib/moordecoy
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
SEED_FLAG=/opt/moorctl/.seeded

PORT_MAIN=5581
PORT_DECOY=5591

DB=moorside
USER=surveyor
PASS='Torren-Feil-3319'

is_ready() { # is_ready PORT
  "$PGBIN/pg_isready" -h 127.0.0.1 -p "$1" -q >/dev/null 2>&1
}

wait_ready() { # wait_ready PORT
  for _ in $(seq 1 60); do
    if is_ready "$1"; then return 0; fi
    sleep 1
  done
  echo "dbctl: postgres did not become ready on port $1" >&2
  return 1
}

start_cluster() { # start_cluster DATA PORT
  local data="$1" port="$2"
  [ -d "$data" ] || return 1
  if ! is_ready "$port"; then
    chown -R postgres:postgres "$data" 2>/dev/null || true
    su postgres -c "$PGBIN/pg_ctl -D '$data' -l '$data/pg.log' -o '-p $port' start" >/dev/null 2>&1 || true
  fi
  wait_ready "$port"
}

stop_cluster() { # stop_cluster DATA PORT
  if is_ready "$2"; then
    su postgres -c "$PGBIN/pg_ctl -D '$1' -m fast stop" >/dev/null 2>&1 || true
  fi
}

psql_sock() { # psql_sock PORT DB "SQL" -- via unix socket (trust), as postgres
  "$PGBIN/psql" -U postgres -p "$1" -d "$2" -tA -v ON_ERROR_STOP=1 -q -c "$3"
}

init_cluster() { # init_cluster DATA PORT
  local data="$1" port="$2"
  if [ ! -f "$data/PG_VERSION" ]; then
    install -d -o postgres -g postgres "$data"
    su postgres -c "$PGBIN/initdb -D '$data' -U postgres --auth=trust --no-locale -E UTF8" >/dev/null
    {
      echo "port = $port"
      echo "listen_addresses = '127.0.0.1'"
    } >> "$data/postgresql.conf"
    # TCP requires the compose-provided password (scram); unix socket stays
    # trust for the role script and verifier.
    sed -i 's/^\(host .*\)trust$/\1scram-sha-256/' "$data/pg_hba.conf"
    chown postgres:postgres "$data/postgresql.conf" "$data/pg_hba.conf"
  fi
  start_cluster "$data" "$port"
}

seed_main() {
  psql_sock "$PORT_MAIN" postgres "DO \$\$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$USER') THEN
      CREATE ROLE $USER LOGIN PASSWORD '$PASS';
    END IF;
  END \$\$;"

  local dbexists
  dbexists=$(psql_sock "$PORT_MAIN" postgres "SELECT 1 FROM pg_database WHERE datname = '$DB'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -U postgres -p "$PORT_MAIN" -O "$USER" "$DB"
  fi

  local tblexists
  tblexists=$(psql_sock "$PORT_MAIN" "$DB" "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='beacons'" | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  psql_sock "$PORT_MAIN" "$DB" "CREATE TABLE beacons (
    beacon_id  serial PRIMARY KEY,
    code       text NOT NULL,
    grid       text NOT NULL,
    strength   integer NOT NULL,
    status     text NOT NULL,
    logged_at  timestamptz NOT NULL DEFAULT now()
  );"
  psql_sock "$PORT_MAIN" "$DB" "INSERT INTO beacons (code, grid, strength, status) VALUES
    ('MRS-01', 'Fen Tor North',  7, 'active'),
    ('MRS-02', 'Fen Tor North',  4, 'idle'),
    ('MRS-03', 'Hale Ridge',    12, 'active'),
    ('MRS-04', 'Hale Ridge',     2, 'offline'),
    ('MRS-05', 'Sourfen Mere',   9, 'active'),
    ('MRS-06', 'Sourfen Mere',   9, 'active'),
    ('MRS-07', 'Old Causeway',   1, 'idle'),
    ('MRS-08', 'Old Causeway',   5, 'active');"
  psql_sock "$PORT_MAIN" "$DB" "GRANT SELECT ON beacons TO $USER;"
}

seed_decoy() {
  psql_sock "$PORT_DECOY" postgres "DO \$\$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$USER') THEN
      CREATE ROLE $USER LOGIN PASSWORD '$PASS';
    END IF;
  END \$\$;"

  local dbexists
  dbexists=$(psql_sock "$PORT_DECOY" postgres "SELECT 1 FROM pg_database WHERE datname = '$DB'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -U postgres -p "$PORT_DECOY" -O "$USER" "$DB"
  fi

  local tblexists
  tblexists=$(psql_sock "$PORT_DECOY" "$DB" "SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='beacons'" | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  # The retired registry: same schema, deliberately ZERO rows.
  psql_sock "$PORT_DECOY" "$DB" "CREATE TABLE beacons (
    beacon_id  serial PRIMARY KEY,
    code       text NOT NULL,
    grid       text NOT NULL,
    strength   integer NOT NULL,
    status     text NOT NULL,
    logged_at  timestamptz NOT NULL DEFAULT now()
  );"
  psql_sock "$PORT_DECOY" "$DB" "GRANT SELECT ON beacons TO $USER;"
}

init_all() {
  if [ -f "$SEED_FLAG" ]; then
    start_cluster "$DATA_MAIN" "$PORT_MAIN"
    start_cluster "$DATA_DECOY" "$PORT_DECOY"
    return 0
  fi
  init_cluster "$DATA_MAIN" "$PORT_MAIN"
  init_cluster "$DATA_DECOY" "$PORT_DECOY"
  seed_main
  seed_decoy
  touch "$SEED_FLAG"
  echo "dbctl: moor atlas postgres ready (main :$PORT_MAIN, decoy :$PORT_DECOY)" >&2
}

cmd="${1:-up}"
case "$cmd" in
  up)    init_all ;;
  ready) is_ready "$PORT_MAIN" && is_ready "$PORT_DECOY" ;;
  stop)  stop_cluster "$DATA_MAIN" "$PORT_MAIN"; stop_cluster "$DATA_DECOY" "$PORT_DECOY" ;;
  start) start_cluster "$DATA_MAIN" "$PORT_MAIN"; start_cluster "$DATA_DECOY" "$PORT_DECOY" ;;
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
