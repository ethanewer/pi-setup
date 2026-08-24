FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/app/data.db')
con.execute('CREATE TABLE customers(id INTEGER PRIMARY KEY, name TEXT)')
con.execute('CREATE TABLE orders(id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id))')
con.execute("INSERT INTO customers(id, name) VALUES (1,'ann')")
con.execute("INSERT INTO customers(id, name) VALUES (2,'bob')")
con.execute("INSERT INTO customers(id, name) VALUES (3,'carol')")
for oid, cid in [(101, 1), (102, 1), (103, 2), (104, 3)]:
    con.execute('INSERT INTO orders(id, customer_id) VALUES (?,?)', (oid, cid))
# Deliberate foreign-key violation: order references a non-existent customer 99.
con.execute('INSERT INTO orders(id, customer_id) VALUES (105, 99)')
con.commit()
con.close()
PY