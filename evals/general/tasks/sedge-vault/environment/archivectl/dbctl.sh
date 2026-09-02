#!/usr/bin/env bash
#
# dbctl.sh -- Sedgevault archive Postgres controller (image infrastructure).
#
# Brings up the PostgreSQL instance described by /app/archive/stack.yaml and
# seeds the scenario exactly once (idempotent). It is deliberately NOT a
# deliverable and never reads /tests; it only runs the cluster and seeds data.
#
# Subcommands:
#   up      init/seed (once) and ensure the instance is running
#   ready   exit 0 when pg_isready succeeds
set -euo pipefail

DATA=/var/lib/sedgepg
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/15/bin
LOGF=/var/lib/sedgepg/pg.log
SEED_FLAG=/opt/archivectl/.seeded
PORT=5541

# Credentials documented by /app/archive/stack.yaml.
APP_DB=herbarium
APP_USER=curator
APP_PASS='Fenwick-Alder-914'

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
    su postgres -c "$PGBIN/pg_ctl -D '$DATA' -l '$LOGF' -o '-p $PORT' start" >/dev/null 2>&1 || true
  fi
  wait_ready
}

# TCP connections must actually authenticate with a password (scram), so a
# wrong user/password derived from the stack file is genuinely rejected.
enforce_scram() {
  local hba="$DATA/pg_hba.conf"
  if grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+scram-sha-256' "$hba"; then
    return 0
  fi
  sed -i -E 's/^(host[[:space:]]+all[[:space:]]+all[[:space:]]+[0-9a-fA-F:.\/]+[[:space:]]+)trust$/\1scram-sha-256/' "$hba"
  su postgres -c "$PGBIN/pg_ctl -D '$DATA' reload" >/dev/null 2>&1 || true
  sleep 1
}

seed_main() {
  # Fully idempotent: provisions missing objects only, inserts baseline rows
  # into an empty table.
  local admin_env="PGPASSWORD=${APP_PASS}"
  env ${admin_env} "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 -q <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'curator') THEN
    CREATE ROLE curator LOGIN SUPERUSER PASSWORD 'Fenwick-Alder-914';
  END IF;
END $$;
SQL

  local dbexists
  dbexists=$("$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -d postgres -tA \
    -c "SELECT 1 FROM pg_database WHERE datname = '${APP_DB}'" | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    "$PGBIN/createdb" -h 127.0.0.1 -p "$PORT" -U postgres -O "$APP_USER" "$APP_DB"
  fi

  local tblexists
  tblexists=$(env ${admin_env} "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U "$APP_USER" -d "$APP_DB" -tA \
    -c "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'specimens'" \
    | tr -d '[:space:]')
  if [ "$tblexists" = "1" ]; then
    return 0
  fi

  env ${admin_env} "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U "$APP_USER" -d "$APP_DB" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE specimens (
  id           serial PRIMARY KEY,
  catalog_code text NOT NULL,
  species      text NOT NULL,
  quadrant     text NOT NULL,
  collected_at date NOT NULL,
  mass_g       integer NOT NULL
);

INSERT INTO specimens (catalog_code, species, quadrant, collected_at, mass_g) VALUES
  ('SH-1041', 'Silene uniflora',          'Q3', '2031-04-12', 214),
  ('SH-1042', 'Dryas octopetala',         'Q1', '2031-04-14',  98),
  ('SH-1043', 'Pinguicula vulgaris',      'Q7', '2031-05-02',  61),
  ('SH-1044', 'Armeria maritima',         'Q3', '2031-05-19', 173),
  ('SH-1045', 'Primula scotica',          'Q2', '2031-06-07',  87),
  ('SH-1046', 'Cerastium nigrescens',     'Q5', '2031-06-21', 129);
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
  # Before the hba tightening the superuser bootstrap below runs over TCP trust.
  seed_main
  enforce_scram
  touch "$SEED_FLAG"
  echo "dbctl: sedgevault postgres ready (seeded)" >&2
}

up() {
  init_db
  start_pg
}

cmd="${1:-up}"
case "$cmd" in
  up)    up ;;
  ready) is_ready ;;
  *)     echo "unknown dbctl subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0
