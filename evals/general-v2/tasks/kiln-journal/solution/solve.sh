#!/bin/bash
# Real oracle for kiln-journal: write the generic replay program, then RUN it on
# the visible fixtures to produce /app/merged.db and /app/merged.json.
# Never reads /tests.
set -eu

cat > /app/solve.py <<'PY'
"""Restore the recovered WAL beside a copy of the database and let SQLite
auto-replay it on open; write merged.db and merged.json."""
import json
import os
import shutil
import sqlite3
import sys
import tempfile

SCHEMA = ("CREATE TABLE readings (\n"
          "  id        INTEGER PRIMARY KEY,\n"
          "  sensor    TEXT NOT NULL,\n"
          "  celsius   REAL NOT NULL,\n"
          "  taken_on  TEXT NOT NULL\n"
          ");")


def solve(input_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    db_src = os.path.join(input_dir, "telemetry.db")
    wal_src = os.path.join(input_dir, "journal", "telemetry.wal")

    scratch = tempfile.mkdtemp(prefix="kiln_replay_", dir=output_dir)
    try:
        db = os.path.join(scratch, "telemetry.db")
        shutil.copyfile(db_src, db)
        if os.path.isfile(wal_src):
            # restore the recovered journal under the expected WAL name so that
            # opening the database auto-replays it
            shutil.copyfile(wal_src, db + "-wal")
        conn = sqlite3.connect(db)
        try:
            rows = [list(r) for r in conn.execute(
                "SELECT id, sensor, celsius, taken_on FROM readings ORDER BY id")]
        finally:
            conn.close()  # closing checkpoints the replayed WAL into the copy

        # write a clean, self-contained merged database
        merged = os.path.join(output_dir, "merged.db")
        if os.path.exists(merged):
            os.remove(merged)
        out = sqlite3.connect(merged)
        try:
            out.execute(SCHEMA)
            out.executemany("INSERT INTO readings VALUES (?,?,?,?)", rows)
            out.commit()
        finally:
            out.close()

        with open(os.path.join(output_dir, "merged.json"), "w", encoding="utf-8") as fh:
            json.dump({"count": len(rows), "rows": rows}, fh, indent=1)
            fh.write("\n")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def main(argv):
    if len(argv) != 3:
        print("usage: solve.py <input_dir> <output_dir>", file=sys.stderr)
        return 2
    solve(argv[1], argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x /app/solve.py

python3 /app/solve.py /app /app

echo "solve.sh done"
ls -l /app/solve.py /app/merged.db /app/merged.json
