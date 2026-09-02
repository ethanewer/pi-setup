#!/bin/bash
set -euo pipefail

cat > /app/build_db.py <<'PY'
import sqlite3

con = sqlite3.connect('/app/books.db')
con.execute('CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT)')
con.execute('CREATE TABLE books(id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, year INTEGER)')
authors = [(1, 'tolkien'), (2, 'asimov'), (3, 'le guin')]
books = [
    (1, 'The Hobbit', 1, 1937),
    (2, 'The Return of the King', 1, 1955),
    (3, 'I, Robot', 2, 1950),
    (4, 'Foundation', 2, 1951),
    (5, 'A Wizard of Earthsea', 3, 1968),
]
con.executemany('INSERT INTO authors(id, name) VALUES(?, ?)', authors)
con.executemany('INSERT INTO books(id, title, author_id, year) VALUES(?, ?, ?, ?)', books)
con.commit()

query = """
SELECT a.name, COUNT(b.id), MIN(b.year)
FROM authors a JOIN books b ON b.author_id = a.id
GROUP BY a.id
ORDER BY a.id;
"""
rows = con.execute(query).fetchall()
with open('/app/result.txt', 'w') as f:
    for name, cnt, myear in rows:
        f.write(f"{name}:{cnt}:{myear}\n")
con.close()
PY

python3 /app/build_db.py