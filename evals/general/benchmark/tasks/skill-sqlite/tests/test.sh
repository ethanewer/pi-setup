#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/books.db ] && [ -f /app/result.txt ]; then
  python3 - <<'PY' && reward=1
import sqlite3

con = sqlite3.connect('/app/books.db')
cur = con.cursor()
# Ensure schema is present
cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables = [r[0] for r in cur.fetchall()]
assert 'authors' in tables and 'books' in tables, tables

query = """
SELECT a.name, COUNT(b.id), MIN(b.year)
FROM authors a JOIN books b ON b.author_id = a.id
GROUP BY a.id
ORDER BY a.id;
"""
expected = [f"{r[0]}:{r[1]}:{r[2]}" for r in cur.execute(query).fetchall()]
lines = [ln.strip() for ln in open('/app/result.txt') if ln.strip()]
assert lines == expected, (lines, expected)
PY
fi
echo "$reward" > /logs/verifier/reward.txt