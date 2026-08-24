FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

# SQLite amalgamation source (sqlite3.c + shell.c + sqlite3.h) shipped in the image.
COPY files/sqlite_src/ /app/sqlite_src/

# Seed a small database that the built shell will be used to query.
RUN cat > /app/seed_sales.db.py <<'PY'
import sqlite3
con = sqlite3.connect('/app/sales.db')
con.execute('CREATE TABLE sales(item TEXT, qty INTEGER)')
rows = [('apple',3),('banana',5),('apple',2),('cherry',7),('banana',1),('apple',4)]
con.executemany('INSERT INTO sales(item, qty) VALUES (?,?)', rows)
con.commit(); con.close()
PY
RUN python3 /app/seed_sales.db.py