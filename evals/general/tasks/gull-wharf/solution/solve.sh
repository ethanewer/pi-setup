#!/bin/bash
# Real oracle for gull-wharf: write the fetch_report.py program, then RUN it on
# the visible compose fixture to produce /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/fetch_report.py"
OUT="/app/report.json"
COMPOSE="/app/stack/compose.yaml"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import os
import re
import subprocess
import sys


def die(msg):
    print("fetch_report: %s" % msg, file=sys.stderr)
    sys.exit(1)


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def parse_compose(path):
    """Parse the documented compose subset: single service, environment map
    with POSTGRES_* keys, ports list with one host->container mapping."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        die("cannot read compose file: %s" % exc)

    env = {}
    host_port = None
    for line in text.splitlines():
        m = re.match(r"^\s+(POSTGRES_(?:DB|USER|PASSWORD))\s*:\s*(.*)$", line)
        if m and m.group(1) not in env:
            env[m.group(1)] = unquote(m.group(2))
            continue
        m = re.match(r'^\s*-\s*"?([^:\s"]*:)?(\d+):(\d+)"?\s*$', line)
        if m and host_port is None:
            host_port = int(m.group(2))
    missing = [k for k in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD") if k not in env]
    if missing or host_port is None:
        die("compose file missing keys: %s port=%s" % (missing, host_port))
    return {
        "host": "127.0.0.1",
        "port": host_port,
        "database": env["POSTGRES_DB"],
        "user": env["POSTGRES_USER"],
        "password": env["POSTGRES_PASSWORD"],
    }


AGG_SQL = (
    "SELECT station, count(*), avg(celsius), max(celsius) "
    "FROM readings GROUP BY station ORDER BY station"
)


def query(conn):
    pg_env = dict(os.environ)
    pg_env["PGPASSWORD"] = conn["password"]
    pg_env["PGCONNECT_TIMEOUT"] = "10"
    pgbin = "/usr/lib/postgresql/16/bin/psql"
    if not os.path.exists(pgbin):
        pgbin = "psql"
    try:
        proc = subprocess.run(
            [pgbin, "-h", conn["host"], "-p", str(conn["port"]),
             "-U", conn["user"], "-d", conn["database"],
             "-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", AGG_SQL],
            env=pg_env, capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        die("connection/query failed: %s" % exc)
    if proc.returncode != 0:
        die("connection/query failed: %s" % proc.stderr.strip()[:300])
    stations = {}
    total = 0
    for row in proc.stdout.splitlines():
        row = row.strip()
        if not row:
            continue
        parts = row.split("\t")
        if len(parts) != 4:
            die("unexpected row shape: %r" % row)
        station, cnt, avg, mx = parts
        stations[station] = {
            "readings": int(cnt),
            "avg_celsius": float(avg),
            "max_celsius": float(mx),
        }
        total += int(cnt)
    return {
        "connection": {
            "host": conn["host"],
            "port": conn["port"],
            "database": conn["database"],
            "user": conn["user"],
        },
        "stations": stations,
        "total_readings": total,
    }


def main():
    if len(sys.argv) != 3:
        die("usage: fetch_report.py <compose_file> <output_json>")
    compose_path, out_path = sys.argv[1], sys.argv[2]
    report = query(parse_compose(compose_path))
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=True)
    os.replace(tmp, out_path)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# ---- 2. Ensure the scenario DB is up (idempotent; blocks until ready), then
# run the produced program on the visible stack to generate the report.
if [ -x /opt/tidectl/dbctl.sh ]; then
  /opt/tidectl/dbctl.sh up >/dev/null 2>&1 || true
fi
python3 "$SOLVER" "$COMPOSE" "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
