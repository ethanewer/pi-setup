#!/bin/bash
set -euo pipefail

cat > /app/explain.py <<'PYEOF'
import sqlite3, json, re, sys

con = sqlite3.connect('/app/sales.db')
cur = con.cursor()
cur.execute("EXPLAIN QUERY PLAN SELECT * FROM sales WHERE region = 'East'")
rows = cur.fetchall()
# rows: (id, parent, notused, detail). Order by (minimal) plan id is the natural order.
plan = [r[3] for r in rows]

uses_index = any('USING INDEX' in d for d in plan)
index_name = None
for d in plan:
    m = re.search(r'USING INDEX\s+(\S+)', d)
    if m:
        index_name = m.group(1).rstrip('(')
        break

out = {'uses_index': uses_index, 'index_name': index_name, 'plan': plan}
with open('/app/plan.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /app/explain.py