#!/usr/bin/env bash
# Meridian Freight warehouse: start the shipped PostgreSQL cluster.
#
# Contract (see instruction.md):
#   - idempotent: safe to run repeatedly, also while the cluster is already up
#   - starts the *stopped* cluster at /srv/pgdata as the postgres OS user
#   - exits 0 only once the cluster accepts connections at 127.0.0.1:5433
#     (database `analytics`, user `postgres`, trust auth)
#   - never changes schema or data; it only starts the server
set -u
PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1)
DATA=/srv/pgdata
PORT=5433
LOG=/tmp/mf-pg.log

is_up() {
  su postgres -c "$PGBIN/pg_isready -h 127.0.0.1 -p $PORT -q" >/dev/null 2>&1
}

if ! is_up; then
  su postgres -c "$PGBIN/pg_ctl -D $DATA -l $LOG -o '-p 5433' start" >/dev/null 2>&1 || true
fi
for _ in $(seq 1 90); do
  is_up && exit 0
  sleep 1
done
echo "meridian postgres did not become ready" >&2
exit 1