#!/bin/bash
# Oracle for pumice-berth: writes the real loader /app/solve.py, then RUNS it
# on the visible scenario (/app -> /app) to produce all deliverables.
# Never reads /tests.
set -eu

SOLVER="/app/solve.py"

cat > "$SOLVER" <<'ORACLE_PY'
#!/usr/bin/env python3
"""solve.py -- Pumice Berth telemetry bulk loader.

Bulk-imports readings.csv into loaded.db through the SQLite client-side COPY
facility (the sqlite3 CLI `.import` dot-command) into a staging table, then
transfers the staged rows into the typed `readings` table and emits
import_log.txt + summary.json.

Usage: python3 solve.py <input_dir> <output_dir>
"""
import json
import os
import sqlite3
import subprocess
import sys

CSV_NAME = "readings.csv"
STAGING = "staging_readings"


def main():
    inp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    schema = open(os.path.join(inp, "schema.sql"), "r", encoding="utf-8").read()

    db_path = os.path.join(out, "loaded.db")
    for suffix in ("", "-wal", "-shm"):
        p = db_path + suffix
        if os.path.exists(p):
            os.remove(p)

    # Fresh database with the prescribed schema plus a TEXT staging table.
    con = sqlite3.connect(db_path)
    con.executescript(schema)
    con.execute(
        "CREATE TABLE staging_readings "
        "(id TEXT, sensor TEXT, metric TEXT, value TEXT, recorded_on TEXT)"
    )
    con.commit()
    con.close()

    # --- the client-side COPY: sqlite3 CLI dot-command `.import` ---
    cli_script = (
        ".mode csv\n"
        ".import --csv --skip 1 %s %s\n"
        "SELECT 'cli_stage_rows', COUNT(*) FROM %s;\n" % (CSV_NAME, STAGING, STAGING)
    )
    proc = subprocess.run(
        ["sqlite3", db_path],
        input=cli_script,
        capture_output=True,
        text=True,
        cwd=inp,
        timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError("sqlite3 CLI copy failed: %s" % proc.stderr)

    transcript = "$ sqlite3 loaded.db   # client-side COPY session (cwd=<input_dir>)\n"
    transcript += cli_script
    transcript += proc.stdout.strip() + "\n"

    # Transfer staged rows into the typed target table.
    con = sqlite3.connect(db_path)
    con.execute(
        "INSERT INTO readings (id, sensor, metric, value, recorded_on) "
        "SELECT CAST(id AS INTEGER), sensor, metric, CAST(value AS REAL), recorded_on "
        "FROM %s" % STAGING
    )
    con.execute("DROP TABLE %s" % STAGING)
    con.commit()

    n = con.execute("SELECT COUNT(*) FROM readings").fetchone()[0]
    metrics = [r[0] for r in con.execute(
        "SELECT DISTINCT metric FROM readings ORDER BY metric")]
    by_metric, avg_by_metric = {}, {}
    for m in metrics:
        by_metric[m] = con.execute(
            "SELECT COUNT(*) FROM readings WHERE metric = ?", (m,)).fetchone()[0]
        avg_value = con.execute(
            "SELECT AVG(value) FROM readings WHERE metric = ?", (m,)).fetchone()[0]
        avg_by_metric[m] = float(avg_value)
    lo, hi = con.execute(
        "SELECT MIN(recorded_on), MAX(recorded_on) FROM readings").fetchone()
    con.close()

    transcript += "loaded_rows: %d\n" % n
    with open(os.path.join(out, "import_log.txt"), "w", encoding="utf-8") as fh:
        fh.write(transcript)

    summary = {
        "total_rows": n,
        "by_metric": by_metric,
        "avg_value_by_metric": avg_by_metric,
        "min_recorded_on": lo,
        "max_recorded_on": hi,
    }
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)


if __name__ == "__main__":
    main()
ORACLE_PY

chmod +x "$SOLVER"

# Run the produced loader on the visible scenario to emit every deliverable.
python3 "$SOLVER" /app /app

echo "solve.sh done -> /app/solve.py, /app/loaded.db, /app/import_log.txt, /app/summary.json"
ls -l "$SOLVER" /app/loaded.db /app/import_log.txt /app/summary.json
