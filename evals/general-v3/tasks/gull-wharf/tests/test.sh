#!/bin/bash
#
# gull-wharf verifier.
# - keeps the scenario DB up (image infra)
# - enforces the no-modify rule on /app/stack/compose.yaml
# - checks both deliverables exist
# - EXECUTES /app/fetch_report.py on the visible compose and on every hidden
#   compose scenario, comparing against a live reference computed directly
#   from each database as the postgres superuser (over the unix socket).
# - the badpass scenario must fail safely (non-zero exit, no output file).
# Writes REWARD (0/1) to /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

PGBIN=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | head -1 || true)
[ -n "${PGBIN-}" ] || PGBIN=/usr/lib/postgresql/16/bin
TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

PRISTINE_COMPOSE_SHA="59186530b0d14f6f25f0061330df65244909e7778955de01ade0b24e65161433"

TMP=$(mktemp -d)
# the postgres OS superuser must be able to read the SQL/TSV files we stage
# here, so open the scratch dir to group/other
chmod 755 "$TMP"
overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
  echo "gull-wharf verifier: overall=$overall${msgs:+:${msgs}}" >&2
}
trap 'finalize_reward; rm -rf "$TMP"' EXIT

note() { msgs="$msgs $1"; }

# --- scenario up ------------------------------------------------------------
$TIMEOUT_CMD 120 /opt/tidectl/dbctl.sh up >/dev/null 2>&1 \
  || { overall=0; note "db:up-failed"; }

# --- no-modify guard --------------------------------------------------------
if [ ! -f /app/stack/compose.yaml ]; then
  overall=0; note "no-modify:compose-missing"
else
  actual=$(sha256sum /app/stack/compose.yaml | awk '{print $1}')
  [ "$actual" = "$PRISTINE_COMPOSE_SHA" ] || { overall=0; note "no-modify:compose-modified"; }
fi

# --- deliverables present ---------------------------------------------------
[ -f /app/fetch_report.py ] || { overall=0; note "missing:fetch_report.py"; }
[ -f /app/report.json ]     || { overall=0; note "missing:report.json"; }

ref_sql() { cat > "$1" <<'SQL'
SELECT station, count(*), avg(celsius), max(celsius)
  FROM readings
 GROUP BY station
 ORDER BY station;
SQL
}

# Compare agent output (json file) with reference rows (tsv from psql socket).
compare() { # compare OUT_JSON FACTS_JSON REF_TSV -> 0 ok
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys

out_path, facts_path, ref_path = sys.argv[1:4]

def norm(x, nd=4):
    return round(float(x), nd)

try:
    got = json.load(open(out_path))
    facts = json.load(open(facts_path))
except Exception as exc:
    print("unreadable output: %s" % exc)
    sys.exit(1)

if not isinstance(got, dict) or set(got.keys()) != {"connection", "stations", "total_readings"}:
    print("bad top-level keys: %s" % (sorted(got.keys()) if isinstance(got, dict) else type(got)))
    sys.exit(1)

want_conn = dict(facts)
want_conn["host"] = "127.0.0.1"
want_conn.pop("password", None)
got_conn = got["connection"]
if not isinstance(got_conn, dict) or got_conn != want_conn:
    print("connection mismatch: %r vs %r" % (got_conn, want_conn))
    sys.exit(1)

# reference rows: station \t count \t avg \t max
want_stations = {}
total = 0
for line in open(ref_path):
    line = line.strip()
    if not line:
        continue
    st, cnt, avg, mx = line.split("|")
    want_stations[st] = {
        "readings": int(cnt),
        "avg_celsius": norm(avg),
        "max_celsius": norm(mx),
    }
    total += int(cnt)

got_stations = got["stations"]
if not isinstance(got_stations, dict) or set(got_stations.keys()) != set(want_stations.keys()):
    print("station keys mismatch: %r vs %r" % (
        sorted(got_stations) if isinstance(got_stations, dict) else got_stations,
        sorted(want_stations)))
    sys.exit(1)
for st, want in want_stations.items():
    g = got_stations[st]
    if not isinstance(g, dict) or set(g.keys()) != {"readings", "avg_celsius", "max_celsius"}:
        print("station %s bad keys" % st)
        sys.exit(1)
    if int(g["readings"]) != want["readings"]:
        print("station %s count mismatch" % st)
        sys.exit(1)
    if norm(g["avg_celsius"]) != want["avg_celsius"] or norm(g["max_celsius"]) != want["max_celsius"]:
        print("station %s avg/max mismatch: %r vs %r" % (st, g, want))
        sys.exit(1)

if int(got["total_readings"]) != total:
    print("total_readings mismatch: %r vs %r" % (got["total_readings"], total))
    sys.exit(1)
sys.exit(0)
PY
}

run_agent() { # run_agent COMPOSE OUT_JSON -> agent rc
  $TIMEOUT_CMD 90 python3 /app/fetch_report.py "$1" "$2" >/dev/null 2>&1
}

pg_retry() { # pg_retry N CMDS...
  local n="$1"; shift
  local try=0
  while [ "$try" -lt "$n" ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    try=$((try+1)); sleep 1
  done
  return 1
}

ensure_cluster() { # ensure_cluster PORT DATA_DIR -> 0 when ready (creates if needed)
  local port="$1" datadir="$2"
  if $PGBIN/pg_isready -h 127.0.0.1 -p "$port" -q >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -f "$datadir/PG_VERSION" ]; then
    mkdir -p "$datadir"
    chown postgres:postgres "$datadir" 2>/dev/null || true
    if ! su postgres -c "$PGBIN/initdb -D '$datadir' -U postgres --auth-local=trust --auth-host=scram-sha-256 --no-locale -E UTF8" >/dev/null 2>&1; then
      return 1
    fi
  fi
  chown -R postgres:postgres "$datadir" 2>/dev/null || true
  su postgres -c "$PGBIN/pg_ctl -D '$datadir' -l '$datadir/pg.log' -o '-p $port' start" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    if $PGBIN/pg_isready -h 127.0.0.1 -p "$port" -q >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

# --- visible case -----------------------------------------------------------
if [ "$overall" = "1" ]; then
  ref_sql "$TMP/ref_visible.sql"
  if ! su postgres -c "$PGBIN/psql -p 5544 -d tidehouse -tA -F'|' -v ON_ERROR_STOP=1 -f $TMP/ref_visible.sql" > "$TMP/ref_visible.tsv" 2>/dev/null; then
    overall=0; note "visible:ref-failed"
  else
    if ! run_agent /app/stack/compose.yaml "$TMP/vis.json"; then
      overall=0; note "visible:agent-run-failed"
    elif ! compare "$TMP/vis.json" /tests/visible_facts.json "$TMP/ref_visible.tsv"; then
      overall=0; note "visible:report-mismatch"
    fi
    if [ "$overall" = "1" ] && ! compare /app/report.json /tests/visible_facts.json "$TMP/ref_visible.tsv"; then
      overall=0; note "visible:deliverable-report-mismatch"
    fi
  fi
fi

# --- hidden scenarios -------------------------------------------------------
scen=0
for dir in /tests/hidden/*/; do
  name=$(basename "$dir")
  [ -f "$dir/compose.yaml" ] || continue
  [ -f "$dir/facts.json" ]   || continue
  scen=$((scen+1))

  if [ -f "$dir/expect_fail" ]; then
    out="$TMP/out_$name.json"
    rm -f "$out"
    rc=0
    run_agent "$dir/compose.yaml" "$out" || rc=1
    if [ "$rc" -eq 0 ]; then
      overall=0; note "$name:should-have-failed"
    elif [ -e "$out" ]; then
      overall=0; note "$name:output-file-created-on-failure"
    fi
    continue
  fi

  [ -f "$dir/seed.sql" ] || { overall=0; note "$name:missing-seed"; continue; }

  port=$(python3 -c "import json;print(json.load(open('$dir/facts.json'))['port'])")
  db=$(python3 -c "import json;print(json.load(open('$dir/facts.json'))['database'])")
  user=$(python3 -c "import json;print(json.load(open('$dir/facts.json'))['user'])")
  pass=$(sed -n 's/.*POSTGRES_PASSWORD:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$dir/compose.yaml")

  # Make sure a cluster is listening on the scenario port (idempotent).
  if [ "$port" = "5544" ]; then
    ensure_cluster 5544 /var/lib/tidedb || { overall=0; note "$name:cluster-5544-not-ready"; continue; }
  else
    ensure_cluster "$port" "/var/lib/cluster_$port" || { overall=0; note "$name:cluster-$port-not-ready"; continue; }
  fi

  # Provision the scenario role/db/seed over the trusted unix socket.
  # The role must exist BEFORE createdb (createdb -O needs it).
  {
    echo "SET password_encryption = 'scram-sha-256';"
    echo "DO \$\$ BEGIN"
    echo "  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$user') THEN"
    echo "    CREATE ROLE $user LOGIN PASSWORD '$pass';"
    echo "  END IF;"
    echo "END \$\$;"
  } > "$TMP/prov_$name.sql"
  if ! pg_retry 5 $TIMEOUT_CMD 60 su postgres -c "$PGBIN/psql -p $port -d postgres -v ON_ERROR_STOP=1 -q -f $TMP/prov_$name.sql"; then
    overall=0; note "$name:role-failed"; continue
  fi
  pg_retry 3 $TIMEOUT_CMD 60 su postgres -c "$PGBIN/dropdb --if-exists -p $port $db" || true
  if ! pg_retry 5 $TIMEOUT_CMD 60 su postgres -c "$PGBIN/createdb -p $port -O $user $db"; then
    overall=0; note "$name:create-failed"; continue
  fi
  if ! pg_retry 5 $TIMEOUT_CMD 60 su postgres -c "$PGBIN/psql -p $port -d $db -v ON_ERROR_STOP=1 -q -f $dir/seed.sql"; then
    overall=0; note "$name:seed-failed"; continue
  fi
  su postgres -c "$PGBIN/psql -p $port -d $db -q -c 'GRANT SELECT ON readings TO $user;'" >/dev/null 2>&1 || true

  # Reference rows over the trusted socket.
  ref_sql "$TMP/ref_$name.sql"
  if ! su postgres -c "$PGBIN/psql -p $port -d $db -tA -F'|' -v ON_ERROR_STOP=1 -f $TMP/ref_$name.sql" > "$TMP/ref_$name.tsv" 2>/dev/null; then
    overall=0; note "$name:ref-failed"; continue
  fi

  if [ "$overall" = "1" ]; then
    out="$TMP/out_$name.json"
    rm -f "$out"
    if ! run_agent "$dir/compose.yaml" "$out"; then
      overall=0; note "$name:agent-run-failed"
    elif ! compare "$out" "$dir/facts.json" "$TMP/ref_$name.tsv"; then
      overall=0; note "$name:report-mismatch"
    fi
  fi
done
[ "$scen" -ge 1 ] || { overall=0; note "hidden:no-scenarios"; }

exit 0
