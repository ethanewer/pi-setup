FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import sqlite3
con = sqlite3.connect('/app/sales.db')
cur = con.cursor()
cur.execute('DROP TABLE IF EXISTS sales')
cur.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY, region TEXT, amount REAL)')
rows = []
regions = ['East', 'West', 'North', 'South']
for i in range(500):
    rows.append((i, regions[i % 4], i * 1.5))
cur.executemany('INSERT INTO sales(id, region, amount) VALUES (?,?,?)', rows)
cur.execute('CREATE INDEX sales_region ON sales(region)')
con.commit()
con.close()
PYEOF