#!/bin/bash
#
# birch-bight oracle. Does the real work: writes the deliverable program that
# derives host/port/database/user/password from a compose-style file and opens
# a live Postgres connection, then runs it on the visible fixture to produce
# /app/verified.csv. Never reads /tests.
set -euo pipefail

# Bring the scenario up (idempotent).
/opt/airctl/dbctl.sh up

SOLVER="/app/pull_readings.py"
OUT="/app/verified.csv"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Pull verified telemetry rows from the airshed Postgres service.

Connection settings (host, port, database, user, password) are derived from
the compose-style service description passed as the first argument.
"""
import csv
import re
import sys

import psycopg2


def _unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1]
    return v


def parse_compose(path):
    env = {}
    port = None
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            m = re.match(r"^(POSTGRES_[A-Z_]+)\s*:\s*(.+?)\s*$", stripped)
            if m:
                env[m.group(1)] = _unquote(m.group(2))
                continue
            # ports entry: "- \"<host>:5432\"" or "- \"<ip>:<host>:5432\""
            m = re.match(
                r'^\s*-\s*["\']?([0-9.]+:)?(\d{1,5}):(\d{1,5})["\']?\s*$', line
            )
            if m:
                if int(m.group(3)) == 5432:
                    port = int(m.group(2))
    user = env.get("POSTGRES_USER")
    password = env.get("POSTGRES_PASSWORD")
    if not user or password is None or port is None:
        raise SystemExit(
            "pull_readings: cannot derive connection settings from %r" % path
        )
    dbname = env.get("POSTGRES_DB") or user
    return "127.0.0.1", port, dbname, user, password


def main():
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: pull_readings.py <compose_file> <output_csv>"
        )
    compose_path, out_path = sys.argv[1], sys.argv[2]
    host, port, dbname, user, password = parse_compose(compose_path)

    conn = psycopg2.connect(
        host=host, port=port, dbname=dbname, user=user, password=password,
        connect_timeout=15,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT site, metric, value FROM readings "
                "WHERE tier = 'verified' ORDER BY id ASC"
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    with open(out_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["site", "metric", "value"])
        for site, metric, value in rows:
            w.writerow([site, metric, value])


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# Run the produced program on the visible fixture to generate the deliverable.
python3 "$SOLVER" /app/airshed/compose.yaml "$OUT"

# Sanity: the connection must actually have yielded the verified rows.
[ -s "$OUT" ] || { echo "oracle: $OUT is empty" >&2; exit 1; }
head -1 "$OUT" | grep -q '^site,metric,value$' || { echo "oracle: bad header" >&2; exit 1; }
nrows=$(( $(wc -l < "$OUT") - 1 ))
[ "$nrows" -ge 1 ] || { echo "oracle: no verified rows pulled" >&2; exit 1; }

echo "birch-bight oracle complete: rows=$nrows"
exit 0
