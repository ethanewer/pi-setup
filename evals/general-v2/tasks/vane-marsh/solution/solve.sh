#!/bin/bash
# Oracle for vane-marsh: write the export program, then RUN it on the visible
# compose fixture to produce /app/report.json.
set -eu

SOLVER="/app/export.py"
OUT="/app/report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Export the Halden Grid metering store described by a compose-style file."""
import json
import os
import re
import subprocess
import sys

QUERY = (
    "SELECT meter, kwh::text, reading_date::text "
    "FROM meter_readings ORDER BY meter, reading_date, kwh"
)


def parse_compose(path):
    """Extract POSTGRES_DB / POSTGRES_USER / POSTGRES_PASSWORD and the
    published HOSTPORT from the compose-style service description."""
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    def scalar(key):
        m = re.search(r'^\s*%s:\s*(.+?)\s*$' % key, text, re.M)
        if not m:
            raise ValueError("missing %s in compose file" % key)
        val = m.group(1).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        return val

    db = scalar("POSTGRES_DB")
    user = scalar("POSTGRES_USER")
    pw = scalar("POSTGRES_PASSWORD")

    pm = re.search(r'ports:\s*\n\s*-\s*"(\d+):\d+"', text)
    if not pm:
        raise ValueError("missing published port in compose file")
    host_port = int(pm.group(1))
    return db, user, pw, host_port


def fetch_rows(db, user, pw, port):
    env = dict(os.environ)
    env["PGPASSWORD"] = pw
    proc = subprocess.run(
        ["psql", "-h", "127.0.0.1", "-p", str(port), "-U", user,
         "-d", db, "-tA", "-F", "|", "-c", QUERY],
        env=env, capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError("psql failed: %s" % proc.stderr.strip()[:400])
    readings = []
    for line in proc.stdout.splitlines():
        line = line.rstrip("\n")
        if not line.strip():
            continue
        meter, kwh_txt, date_txt = line.split("|", 2)
        readings.append(
            {"meter": meter, "kwh": float(kwh_txt), "reading_date": date_txt}
        )
    readings.sort(key=lambda r: (r["meter"], r["reading_date"], r["kwh"]))
    return readings


def main():
    compose_path, out_path = sys.argv[1], sys.argv[2]
    db, user, pw, port = parse_compose(compose_path)
    readings = fetch_rows(db, user, pw, port)
    report = {
        "database": db,
        "user": user,
        "row_count": len(readings),
        "readings": readings,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible fixture.
python3 "$SOLVER" /app/grid/compose.yaml "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
