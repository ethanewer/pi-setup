#!/usr/bin/env bash
#
# dbctl.sh -- wale-ferry MariaDB controller (image infrastructure).
#
# Starts, seeds, stops and resets the live MariaDB instance that the task
# scenario runs against. Purely operational: it never reads /tests, ships no
# answer content, and is deliberately NOT a deliverable.
#
# Subcommands:
#   up       start the server if needed and seed a pristine analytics database
#            if one does not exist yet (idempotent)
#   ready    exit 0 when the server answers on the socket
#   stop     stop the server cleanly
#   reset    stop, discard the analytics database, restore the pristine state
#            (used by the verifier; also handy while iterating)
#   status   print a one-line state snapshot
set -u

DATA=/var/lib/mysql
SOCK=/run/mysqld/mysqld.sock
PIDFILE=/run/mysqld/mysqld.pid
SEED_SQL=/opt/warehouse/seed.sql
SEED_FLAG=/opt/warehouse/.seeded
ERRLOG="$DATA/dbctl.err"

is_ready() {
  mariadb --socket="$SOCK" -N -e "SELECT 1" >/dev/null 2>&1
}

wait_ready() {
  for _ in $(seq 1 120); do
    if is_ready; then return 0; fi
    sleep 1
  done
  echo "dbctl: mariadb did not become ready" >&2
  return 1
}

start_daemon() {
  mkdir -p /run/mysqld
  chown mysql:mysql /run/mysqld
  if ! is_ready; then
    /usr/sbin/mariadbd --user=mysql --datadir="$DATA" --socket="$SOCK" \
      --port=3306 --bind-address=127.0.0.1 --skip-name-resolve \
      --secure-file-priv= --pid-file="$PIDFILE" --log-error="$ERRLOG" &
    sleep 2
  fi
  wait_ready
}

stop_daemon() {
  if is_ready; then
    mariadb-admin --socket="$SOCK" shutdown >/dev/null 2>&1 || true
  fi
  for _ in $(seq 1 60); do
    is_ready || return 0
    sleep 1
  done
  return 0
}

seed_pristine() {
  timeout 600 mariadb --socket="$SOCK" < "$SEED_SQL" >/dev/null 2>&1 || return 1
  touch "$SEED_FLAG"
  return 0
}

needs_seed() {
  [ -f "$SEED_FLAG" ] && mariadb --socket="$SOCK" -N \
    -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='analytics'" \
      | grep -q '^analytics$'
}

start_seeded() {
  start_daemon
  if ! needs_seed; then
    echo "dbctl: seeding pristine analytics database..." >&2
    seed_pristine || { echo "dbctl: seed failed" >&2; return 1; }
  fi
}

cmd="${1:-up}"
case "$cmd" in
  up)      start_seeded ;;
  ready)   is_ready ;;
  stop)    stop_daemon ;;
  reset)
    stop_daemon
    rm -f "$SEED_FLAG"
    start_seeded
    ;;
  status)
    if is_ready; then
      ver=$(mariadb --socket="$SOCK" -N -e 'SELECT VERSION()' 2>/dev/null || echo 'n/a')
      echo "up: $ver"
    else
      echo "down"
    fi
    ;;
  *) echo "dbctl: unknown subcommand: $cmd" >&2; exit 2 ;;
esac
exit 0