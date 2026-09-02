#!/bin/bash
#
# birch-bight verifier.
# Executes the deliverable /app/pull_readings.py on the visible compose fixture
# and on every hidden case in /tests/hidden (different ports notation, missing
# POSTGRES_DB, different credentials/databases/rows), and checks the visible
# deliverable /app/verified.csv. Writes the reward to
# /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=0
msgs=""

finalize_reward() {
  printf '%s' "$overall" > /logs/verifier/reward.txt
}
trap 'finalize_reward; ' EXIT

printf 0 > /logs/verifier/reward.txt

fail() { msgs="$msgs $1"; }

# Bring the scenario up (idempotent image infrastructure).
$TIMEOUT_CMD 120 /opt/airctl/dbctl.sh up >/dev/null 2>&1 \
  || fail "db:up-failed"

[ -f /app/pull_readings.py ] || fail "missing:/app/pull_readings.py"
[ -f /app/verified.csv ]     || fail "missing:/app/verified.csv"

# CSV comparison, fully guarded (a bad parse is a failure, never a crash).
check_csv() { # check_csv <got> <expected> -> 0 ok
  python3 - "$1" "$2" <<'PY'
import sys

def load(p):
    try:
        lines = open(p, encoding="utf-8").read().splitlines()
    except OSError:
        return None
    if not lines or lines[0].strip() != "site,metric,value":
        return None
    rows = []
    for ln in lines[1:]:
        if ln.strip() == "":
            continue
        parts = ln.split(",")
        if len(parts) != 3:
            return None
        try:
            v = float(parts[2])
        except ValueError:
            return None
        rows.append((parts[0].strip(), parts[1].strip(), v))
    return rows

a = load(sys.argv[1])
b = load(sys.argv[2])
if a is None or b is None:
    sys.exit(1)
if len(a) != len(b):
    sys.exit(1)
for (sa, ma, va), (sb, mb, vb) in zip(a, b):
    if sa != sb or ma != mb or abs(va - vb) > 1e-6:
        sys.exit(1)
sys.exit(0)
PY
}

if [ -f /app/pull_readings.py ]; then
  # --- visible case: EXECUTE the deliverable on the live supplied fixture ---
  if [ ! -f /app/airshed/compose.yaml ]; then
    fail "visible:compose-missing"
  else
    rm -f /tmp/bb_vis.csv
    $TIMEOUT_CMD 60 python3 /app/pull_readings.py /app/airshed/compose.yaml /tmp/bb_vis.csv >/dev/null 2>&1 \
      || fail "visible:run-failed"
    if ! check_csv /tmp/bb_vis.csv /tests/expected.csv; then
      fail "visible:mismatch"
      echo "--- diagnostic: /tests listing" >&2
      ls -la /tests >&2 || true
      echo "--- diagnostic: got CSV" >&2
      cat -A /tmp/bb_vis.csv >&2 || true
      echo "--- diagnostic: expected CSV" >&2
      cat -A /tests/expected.csv >&2 || true
    fi
  fi

  # --- visible-case deliverable: /app/verified.csv must match too ---
  check_csv /app/verified.csv /tests/expected.csv || fail "verified.csv:mismatch"

  # --- hidden cases: genuinely distinct compose files + databases ---
  pg_retry() { # pg_retry N CMD...
    local n="$1"; shift
    local try=0
    while [ "$try" -lt "$n" ]; do
      if "$@" >/dev/null 2>&1; then return 0; fi
      try=$((try+1)); sleep 1
    done
    return 1
  }

  scen=0
  for dir in /tests/hidden/*/; do
    name=$(basename "$dir")
    [ -f "${dir}compose.yaml" ] || continue
    [ -f "${dir}setup.sql" ]    || continue
    [ -f "${dir}cleanup.sql" ]  || continue
    [ -f "${dir}expected.csv" ] || continue
    scen=$((scen+1))
    # clean slate for this case (drop role too so stale passwords never linger)
    pg_retry 3 $TIMEOUT_CMD 60 su postgres -c "psql -p 5433 -d postgres -v ON_ERROR_STOP=1 -q -f ${dir}cleanup.sql" \
      || fail "$name:cleanup-failed"
    if ! pg_retry 5 $TIMEOUT_CMD 90 su postgres -c "psql -p 5433 -d postgres -v ON_ERROR_STOP=1 -q -f ${dir}setup.sql"; then
      fail "$name:setup-failed"
      continue
    fi
    rm -f /tmp/bb_case.csv
    if ! $TIMEOUT_CMD 60 python3 /app/pull_readings.py "${dir}compose.yaml" /tmp/bb_case.csv >/dev/null 2>&1; then
      fail "$name:run-failed"
      continue
    fi
    check_csv /tmp/bb_case.csv "${dir}expected.csv" || fail "$name:mismatch"
    pg_retry 3 $TIMEOUT_CMD 60 su postgres -c "psql -p 5433 -d postgres -v ON_ERROR_STOP=1 -q -f ${dir}cleanup.sql" \
      || true
  done
  [ "$scen" -ge 1 ] || fail "hidden:no-cases"
fi

if [ -z "$(echo "$msgs" | tr -d '[:space:]')" ]; then
  overall=1
else
  echo "birch-bight verifier FAIL:$msgs" >&2
fi
exit 0
