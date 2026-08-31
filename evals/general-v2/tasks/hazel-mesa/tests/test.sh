#!/bin/bash
#
# hazel-mesa verifier.
# Executes the deliverable /app/warehouse_dump.py on the visible stack and on
# hidden stack/instance pairs (different ports, credentials, rows, decoy
# services), checks /app/telemetry.csv against the visible expectation, and
# checks the failure contract on a malformed stack. Writes REWARD (0/1) to
# /logs/verifier/reward.txt on EVERY exit path (EXIT trap).
set -u

mkdir -p /logs/verifier

PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
SOCKDIR=/var/run/postgresql

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT

# Deterministic 0 up front; the trap overwrites with the true result.
printf 0 > /logs/verifier/reward.txt

log() { echo "hazel-mesa verify: $*" >&2; }

# Keep the visible scenario live (idempotent, in the image).
$TIMEOUT_CMD 120 /opt/obsctl/dbctl.sh up >/dev/null 2>&1 \
  || { overall=0; msgs="$msgs main:up-failed"; }

# ---------------------------------------------------------------------------
# Temp-cluster helper for hidden instances (SCRAM host auth, trust socket).
# ---------------------------------------------------------------------------
ensure_cluster() { # $1 = port
  local port="$1" dir="/tmp/pgtmp-$port"
  if su postgres -c "$PGBIN/pg_isready -h $SOCKDIR -p $port -q" >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -f "$dir/PG_VERSION" ]; then
    install -d -o postgres -g postgres "$dir"
    if ! su postgres -c "$PGBIN/initdb -D '$dir' -U postgres \
        --auth-local=trust --auth-host=scram-sha-256 --no-locale -E UTF8" >/dev/null 2>&1; then
      return 1
    fi
    su postgres -c "echo 'port = $port' >> '$dir/postgresql.conf'"
  fi
  if ! su postgres -c "$PGBIN/pg_ctl -D '$dir' -l '$dir/pg.log' start" >/dev/null 2>&1; then
    log "cluster $port: start failed" >&2
  fi
  for _ in $(seq 1 30); do
    su postgres -c "$PGBIN/pg_isready -h $SOCKDIR -p $port -q" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# seed_case PORT DB USER PASS SEEDFILE
# Creates role/db if missing (superuser via socket), then seeds the table by
# connecting AS the case user over TCP (so wrong credentials would fail here).
seed_case() {
  local port="$1" db="$2" user="$3" pass="$4" seedfile="$5"
  ensure_cluster "$port" || return 1

  local p_esc="${pass//\'/\'\'}"
  su postgres -c "$PGBIN/psql -h $SOCKDIR -p $port -U postgres -v ON_ERROR_STOP=1 -q -f -" \
    >/dev/null <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${user}') THEN
    CREATE ROLE "${user}" LOGIN PASSWORD '${p_esc}';
  END IF;
END \$\$;
SQL
  local dbexists
  dbexists=$(su postgres -c "$PGBIN/psql -h $SOCKDIR -p $port -U postgres -tA -c \
    \"SELECT 1 FROM pg_database WHERE datname = '$db'\"" 2>/dev/null | tr -d '[:space:]')
  if [ "${dbexists:-0}" != "1" ]; then
    su postgres -c "$PGBIN/createdb -h $SOCKDIR -p $port -U postgres -O '$user' '$db'" || return 1
  fi
  # Seed THROUGH the case user's own TCP credentials (validates they work).
  PGPASSWORD="$pass" $TIMEOUT_CMD 60 "$PGBIN/psql" -h 127.0.0.1 -p "$port" -U "$user" \
    -d "$db" -v ON_ERROR_STOP=1 -q -f "$seedfile"
}

# ---------------------------------------------------------------------------
# Guarded CSV comparison helper (python; guards every parse).
# ---------------------------------------------------------------------------
compare_csv() { # compare_csv GOT EXPECTED -> 0 ok
  python3 - "$1" "$2" <<'PY'
import sys
try:
    got = open(sys.argv[1], encoding="utf-8").read().strip()
    want = open(sys.argv[2], encoding="utf-8").read().strip()
except Exception as exc:
    print("compare error: %s" % exc, file=sys.stderr)
    sys.exit(1)
sys.exit(0 if got == want else 1)
PY
}

# ---------------------------------------------------------------------------
# Deliverables + visible case
# ---------------------------------------------------------------------------
[ -f /app/warehouse_dump.py ] || { overall=0; msgs="$msgs missing:warehouse_dump.py"; }
[ -f /app/telemetry.csv ]     || { overall=0; msgs="$msgs missing:telemetry.csv"; }

if [ "$overall" = "1" ]; then
  rm -f /tmp/hm_vis.csv
  if ! $TIMEOUT_CMD 60 python3 /app/warehouse_dump.py /app/warehouse/compose.yaml /tmp/hm_vis.csv; then
    overall=0; msgs="$msgs visible:script-failed"
  fi
  if ! compare_csv /tmp/hm_vis.csv /tests/expected_visible.csv; then
    overall=0; msgs="$msgs visible:script-output-mismatch"
  fi
  if ! compare_csv /app/telemetry.csv /tests/expected_visible.csv; then
    overall=0; msgs="$msgs visible:telemetry.csv-mismatch"
  fi
fi

# ---------------------------------------------------------------------------
# Hidden cases: hidden compose + live instance + seed + expected CSV
# ---------------------------------------------------------------------------
scen=0
for dir in /tests/hidden/*/; do
  name=$(basename "$dir")
  [ -f "$dir/case.env" ] && [ -f "$dir/compose.yaml" ] \
    && [ -f "$dir/seed.sql" ] && [ -f "$dir/expected.csv" ] || continue
  scen=$((scen+1))
  unset PORT DB USER PASS 2>/dev/null || true
  # shellcheck disable=SC1091
  . "$dir/case.env" 2>/dev/null || { overall=0; msgs="$msgs $name:env"; continue; }
  PORT=${PORT:-} DB=${DB:-} USER=${USER:-} PASS=${PASS:-}
  if [ -z "$PORT" ] || [ -z "$DB" ] || [ -z "$USER" ] || [ -z "$PASS" ]; then
    overall=0; msgs="$msgs $name:env-incomplete"; continue
  fi

  if ! seed_case "$PORT" "$DB" "$USER" "$PASS" "$dir/seed.sql"; then
    overall=0; msgs="$msgs $name:seed-failed"; continue
  fi

  out="/tmp/hm_hidden_$name.csv"
  rm -f "$out"
  if ! $TIMEOUT_CMD 90 python3 /app/warehouse_dump.py "$dir/compose.yaml" "$out" \
      >"$out.log" 2>&1; then
    overall=0; msgs="$msgs $name:script-failed"
    continue
  fi
  if ! compare_csv "$out" "$dir/expected.csv"; then
    overall=0; msgs="$msgs $name:output-mismatch"
  fi
done
[ "$scen" -ge 1 ] || { overall=0; msgs="$msgs hidden:no-cases"; }

# ---------------------------------------------------------------------------
# Failure-contract check: a compose with no postgres service must be rejected.
# ---------------------------------------------------------------------------
if [ -f /tests/hidden/negative/compose.yaml ]; then
  rm -f /tmp/hm_neg.csv
  if $TIMEOUT_CMD 30 python3 /app/warehouse_dump.py \
      /tests/hidden/negative/compose.yaml /tmp/hm_neg.csv >/dev/null 2>&1; then
    overall=0; msgs="$msgs negative:accepted-bad-stack"
  elif [ -f /tmp/hm_neg.csv ]; then
    overall=0; msgs="$msgs negative:created-output"
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0
