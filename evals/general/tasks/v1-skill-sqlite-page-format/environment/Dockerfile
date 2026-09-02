FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/app/data.db')
con.execute('CREATE TABLE docs(id INTEGER, body TEXT)')
# Insert enough rows so the database spans multiple pages (default page size 4096).
payload = ('x' * 350)
rows = [(i, payload) for i in range(4000)]
con.executemany('INSERT INTO docs(id, body) VALUES (?, ?)', rows)
con.commit()
con.close()
PY