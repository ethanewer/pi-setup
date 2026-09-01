FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/app/store.db')
con.execute('CREATE TABLE orders(id INTEGER PRIMARY KEY, customer TEXT, amount REAL)')
rows = [
    ('alice', 100.0), ('alice', 5.5), ('bob', 200.0), ('bob', 7.0),
    ('carol', 1.0), ('alice', 3.0), ('dave', 9.5), ('bob', 44.0),
]
con.executemany('INSERT INTO orders(customer, amount) VALUES(?, ?)', rows)
con.execute('CREATE INDEX idx_orders_customer ON orders(customer)')
con.commit()
con.close()
PY