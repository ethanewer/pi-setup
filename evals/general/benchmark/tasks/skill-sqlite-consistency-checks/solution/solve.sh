#!/bin/bash
set -euo pipefail

cat > /app/checks.py <<'PY'
import sqlite3

con = sqlite3.connect('/app/data.db')
with open('/app/integrity.txt', 'w') as f:
    for row in con.execute('PRAGMA integrity_check'):
        f.write(str(row[0]) + "\n")
with open('/app/fks.txt', 'w') as f:
    rows = con.execute('PRAGMA foreign_key_check').fetchall()
    if rows:
        for row in rows:
            table, rowid, parent = row[0], row[1], row[2]
            f.write(f"{table}\t{rowid}\t{parent}\n")
    else:
        f.write("\n")
con.close()
PY

python3 /app/checks.py