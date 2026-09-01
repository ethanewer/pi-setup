#!/bin/bash
set -euo pipefail

cat > /app/plan.py <<'PY'
import sqlite3

con = sqlite3.connect('/app/store.db')
rows = con.execute(
    "EXPLAIN QUERY PLAN SELECT * FROM orders WHERE customer = 'alice';"
).fetchall()
with open('/app/plan.txt', 'w') as f:
    for r in rows:
        # r is (id, parent, notused, detail)
        f.write(r[3] + "\n")
con.close()
PY

python3 /app/plan.py