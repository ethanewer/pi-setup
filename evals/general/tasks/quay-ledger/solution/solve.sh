#!/bin/bash
# Oracle for quay-ledger: write the general load program, then RUN it on the
# visible scenario (/app -> /app) to produce the deliverables. Never reads /tests.
set -eu

SOLVER="/app/solve.py"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import os
import sqlite3
import subprocess
import sys

SCHEMA = """CREATE TABLE readings (
  station_id  INTEGER PRIMARY KEY,
  region      TEXT NOT NULL,
  observed_on TEXT NOT NULL,
  temp_c      REAL NOT NULL,
  humidity    REAL NOT NULL
);
"""


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: python3 solve.py <input_dir> <output_dir>\n")
        return 2
    in_dir = os.path.abspath(sys.argv[1])
    out_dir = os.path.abspath(sys.argv[2])
    os.makedirs(out_dir, exist_ok=True)

    csv_path = os.path.join(in_dir, "stations.csv")
    db_path = os.path.join(out_dir, "loaded.db")
    if os.path.exists(db_path):
        os.unlink(db_path)

    # Client-side COPY: sqlite3 CLI dot-command .import (not INSERT loops).
    script = SCHEMA + ".mode csv\n.import --csv --skip 1 \"%s\" readings\n" % csv_path
    proc = subprocess.run(["sqlite3", db_path], input=script, text=True,
                          capture_output=True)
    if proc.returncode != 0 or not os.path.exists(db_path):
        # Fallback for CLI builds without --skip: strip the header into a
        # temp file, then .import that. Still a genuine client copy.
        if os.path.exists(db_path):
            os.unlink(db_path)
        import csv as _csv
        headless = os.path.join(out_dir, "_headless.csv")
        with open(csv_path, newline="") as fin, \
             open(headless, "w", newline="") as fout:
            r = _csv.reader(fin)
            next(r, None)
            _csv.writer(fout).writerows(r)
        script = SCHEMA + ".mode csv\n.import --csv \"%s\" readings\n" % headless
        proc = subprocess.run(["sqlite3", db_path], input=script, text=True,
                              capture_output=True)
        if os.path.exists(headless):
            os.unlink(headless)
        if proc.returncode != 0:
            sys.stderr.write(proc.stderr)
            return 1

    con = sqlite3.connect(db_path)
    rows = con.execute(
        "SELECT station_id, region, observed_on, temp_c, humidity "
        "FROM readings ORDER BY station_id"
    ).fetchall()
    regions = [r[0] for r in con.execute(
        "SELECT DISTINCT region FROM readings ORDER BY region"
    ).fetchall()]
    con.close()

    report = {"rows_loaded": len(rows), "regions": regions}
    with open(os.path.join(out_dir, "load_report.json"), "w") as fh:
        json.dump(report, fh, indent=2)

    with open(os.path.join(out_dir, "import_log.txt"), "w") as fh:
        fh.write("method: sqlite3 client-side COPY (the .import dot-command)\n")
        fh.write("csv: %s\n" % csv_path)
        fh.write("commands executed:\n")
        fh.write(".mode csv\n")
        fh.write(".import --csv --skip 1 \"%s\" readings\n" % csv_path)
        fh.write("rows loaded: %d\n" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible scenario to generate outputs.
python3 "$SOLVER" /app /app

echo "solve.sh done -> $SOLVER and /app artifacts"
ls -l "$SOLVER" /app/loaded.db /app/load_report.json /app/import_log.txt
