# SQLite consistency checks

`/app/data.db` is a SQLite database with the schema:

- `customers(id INTEGER PRIMARY KEY, name TEXT)`
- `orders(id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id))`

One order row deliberately references a `customer_id` (99) that has **no** matching `customers` row, so the database contains a **foreign-key violation**.

Your task is to run SQLite's built-in consistency diagnostics and save their raw output.

Write a Python script `/app/checks.py` that:

1. Connects to `/app/data.db` with `sqlite3`.
2. Runs `PRAGMA integrity_check` (checks the overall structural integrity of the database file — returns one row per issue; a healthy database returns a single `ok`).
3. Runs `PRAGMA foreign_key_check` (returns one row per foreign-key violation, each row having three columns: the child table name, the rowid of the offending row, and the parent table name).
4. Writes results to two files:

   - `/app/integrity.txt` — one line per row returned by `PRAGMA integrity_check` (just the first column's value of each row).
   - `/app/fks.txt` — one line per row returned by `PRAGMA foreign_key_check`, formatted as `<table>\t<rowid>\t<parent>`. If there are no violations, the file contains a single empty line.

Run `/app/checks.py` so both output files exist.

The verifier opens `/app/data.db`, reruns the same two `PRAGMA` commands itself, and requires `/app/integrity.txt` and `/app/fks.txt` to contain exactly the same rows (tolerating trailing whitespace and CRLF).