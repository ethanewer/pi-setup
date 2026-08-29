#!/usr/bin/env bash
#
# quartz-cipher verifier.
# Executes the deliverable /app/query.sql on the live Postgres, enforces the
# strict single-statement format, proves the committed 'wal-committed' batch is
# durable across a crash restart, validates /app/confirm.txt, then re-runs
# /app/query.sql on hidden database scenarios and on malformed-format fixtures.
#
# The reward file is written on EVERY exit path: a scalar is kept in $overall
# and an EXIT trap finalizes /logs/verifier/reward.txt no matter which branch
# is taken (normal completion, an early guard, or a signal). Each database
# command is bounded with `timeout` so a hung Postgres can never consume the
# whole verifier budget before the trap finalises the reward.
set -u

mkdir -p /logs/verifier

PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

TMP=$(mktemp -d)

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward; rm -rf "$TMP"' EXIT

# Seed a deterministic 0 up front; the EXIT trap above will overwrite with the
# true result on every path (including any early exit / signal).
printf 0 > /logs/verifier/reward.txt

runq() { # runq DB "SQL" -> row output
  local db="$1"; local cmd="$2"
  PGPASSWORD=Devlet-Kora-5572 ${TIMEOUT_CMD} 45 "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U durable \
    -d "$db" -tA -F'|' -v ON_ERROR_STOP=1 -c "$cmd" 2>/dev/null
}

runqfile() { # runqfile DB sqlfile -> normalized rows
  local db="$1"; local f="$2"
  PGPASSWORD=Devlet-Kora-5572 $TIMEOUT_CMD 45 "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U durable \
    -d "$db" -tA -F'|' -v ON_ERROR_STOP=1 -f "$f" 2>/dev/null \
    | sed 's/[[:space:]]*$//; s/^[[:space:]]*//'
}

check_format() { # $1 path -> 0 ok, 1 bad
  python3 - "$1" <<'PY'
import sys
try:
    text = open(sys.argv[1], encoding='utf-8').read()
except FileNotFoundError:
    sys.exit(1)
if '--' in text or '/*' in text or '*/' in text:
    sys.exit(1)
s = text.rstrip()
if s.count(';') != 1 or not s.endswith(';'):
    sys.exit(1)
up = s[:-1].strip().upper()
if not (up.startswith('SELECT') or up.startswith('WITH')):
    sys.exit(1)
sys.exit(0)
PY
}

ref_query() { cat > "$1" <<'SQL'
SELECT sku, qty, destination
  FROM shipments
 WHERE batch = 'wal-committed'
 ORDER BY sku;
SQL
}

# Keep the scenario live (idempotent infrastructure, in the image). A failure
# here is recorded (overall=0) rather than silently exiting.
$TIMEOUT_CMD 120 /opt/wardctl/dbctl.sh up >/dev/null 2>&1 \
  || { overall=0; msgs="$msgs db:up-failed"; }

# ---------------------------------------------------------------------------
# Main scenario (database "shipping")
# ---------------------------------------------------------------------------
[ -f /app/query.sql ]   || { overall=0; msgs="$msgs missing:query.sql"; }
[ -f /app/confirm.txt ] || { overall=0; msgs="$msgs missing:confirm.txt"; }

if [ "$overall" = "1" ] && ! check_format /app/query.sql; then
  overall=0; msgs="$msgs format:rejected"
fi

# Durability: the committed batch must survive a crash restart (WAL replay).
if [ "$overall" = "1" ]; then
  before=$(runq shipping "SELECT count(*) FROM shipments WHERE batch='wal-committed';" | tr -d '[:space:]')
  $TIMEOUT_CMD 90 /opt/wardctl/dbctl.sh restart >/dev/null 2>&1
  after=$(runq shipping "SELECT count(*) FROM shipments WHERE batch='wal-committed';" | tr -d '[:space:]')
  if [ "${before:-0}" -lt 1 ]; then
    overall=0; msgs="$msgs durability:no-committed-batch"
  fi
  if [ "${before:-0}" != "${after:-0}" ]; then
    overall=0; msgs="$msgs durability:loss-after-restart"
  fi
fi

if [ "$overall" = "1" ]; then
  ref_query "$TMP/ref.sql"
  if ! diff -q <(runqfile shipping /app/query.sql | sort) \
               <(runqfile shipping "$TMP/ref.sql" | sort) >/dev/null; then
    overall=0; msgs="$msgs main:query-mismatch"
  fi
fi

if [ -f /app/confirm.txt ] && [ "$overall" = "1" ]; then
  grep -q 'wal-committed' /app/confirm.txt || { overall=0; msgs="$msgs confirm:no-marker"; }
  grep -qi 'durab' /app/confirm.txt          || { overall=0; msgs="$msgs confirm:no-durability"; }
fi

# ---------------------------------------------------------------------------
# Hidden database scenarios (same schema + marker, different rows)
# ---------------------------------------------------------------------------
# A small retry helper: under a single-CPU Postgres the createdb/psql -f pair
# may transiently collide with a just-finished backend. Retrying a handful of
# times keeps the hidden scenarios reliable without weakening any check — the
# query result comparison itself stays strict.
pg_retry() { # pg_retry N CMDS...
  local n="$1"; shift
  local try=0
  while [ "$try" -lt "$n" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    try=$((try+1)); sleep 1
  done
  return 1
}

scen=0
for dir in /tests/hidden/*/; do
  name=$(basename "$dir")
  [ -f "$dir/seed.sql" ] || continue
  scen=$((scen+1))
  pg_retry 3 $TIMEOUT_CMD 80 "$PGBIN/dropdb" --if-exists -h 127.0.0.1 -p 5432 -U postgres "$name" \
    || true
  if ! pg_retry 5 $TIMEOUT_CMD 80 "$PGBIN/createdb" -h 127.0.0.1 -p 5432 -U postgres -O postgres "$name"; then
    overall=0; msgs="$msgs $name:create-failed"; continue
  fi
  if ! pg_retry 5 $TIMEOUT_CMD 80 "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d "$name" -v ON_ERROR_STOP=1 -q \
      -f "$dir/seed.sql"; then
    overall=0; msgs="$msgs $name:seed-failed"; continue
  fi
  pg_retry 3 $TIMEOUT_CMD 80 "$PGBIN/psql" -h 127.0.0.1 -p 5432 -U postgres -d "$name" -v ON_ERROR_STOP=1 -q \
      -c "GRANT SELECT ON shipments TO durable;" || true

  if [ "$overall" = "1" ]; then
    ref_query "$TMP/ref_$name.sql"
    runqfile "$name" /app/query.sql | sort       > "$TMP/q_$name.out"
    runqfile "$name" "$TMP/ref_$name.sql" | sort > "$TMP/r_$name.out"
    if ! diff -q "$TMP/q_$name.out" "$TMP/r_$name.out" >/dev/null; then
      overall=0; msgs="$msgs $name:query-mismatch"
      diff "$TMP/r_$name.out" "$TMP/q_$name.out" >&2 || true
    fi
  fi
  pg_retry 3 $TIMEOUT_CMD 80 "$PGBIN/dropdb" --if-exists -h 127.0.0.1 -p 5432 -U postgres "$name" \
  || true
done
[ "$scen" -ge 1 ] || { overall=0; msgs="$msgs hidden:no-scenarios"; }

# ---------------------------------------------------------------------------
# Format strictness fixtures (every one must be rejected)
# ---------------------------------------------------------------------------
fcnt=0
for f in /tests/hidden/format/*.sql; do
  [ -f "$f" ] || continue
  fcnt=$((fcnt+1))
  if check_format "$f"; then
    overall=0; msgs="$msgs format:should-reject-$(basename "$f")"
  fi
done
[ "$fcnt" -ge 1 ] || { overall=0; msgs="$msgs format:no-fixtures"; }

if [ "$overall" = "1" ]; then
  finalize_reward
else
  echo "quartz-cipher verifier FAIL${msgs:+:${msgs}}" >&2
  finalize_reward
fi
exit 0