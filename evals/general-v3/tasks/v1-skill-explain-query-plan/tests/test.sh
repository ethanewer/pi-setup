#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/plan.json ]; then
  if python3 - <<'PYEOF'
import sqlite3, json, re
con = sqlite3.connect('/app/sales.db')
cur = con.cursor()
cur.execute("EXPLAIN QUERY PLAN SELECT * FROM sales WHERE region = 'East'")
rows = cur.fetchall()
plan = [r[3] for r in rows]
uses_index = any('USING INDEX' in d for d in plan)
index_name = None
for d in plan:
    m = re.search(r'USING INDEX\s+(\S+)', d)
    if m:
        index_name = m.group(1).rstrip('(')
        break
exp = {'uses_index': uses_index, 'index_name': index_name, 'plan': plan}
got = json.load(open('/app/plan.json'))
assert got == exp, (got, exp)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt