# SQL query plans

`/app/store.db` is a SQLite database with a table `orders(id INTEGER PRIMARY KEY, customer TEXT, amount REAL)` and an index:

```sql
CREATE INDEX idx_orders_customer ON orders(customer);
```

The index is specifically designed to speed up lookups on the `customer` column.

Your task is to inspect the **query plan** that SQLite uses to execute the query:

```sql
SELECT * FROM orders WHERE customer = 'alice';
```

Write a Python script `/app/plan.py` that:

1. Connects to `/app/store.db` using Python's `sqlite3` module.
2. Runs `EXPLAIN QUERY PLAN <the query above>` (SQLite's built-in query-plan diagnostic — it does not execute the query; it reports how the query would be evaluated).
3. Collects the output rows and writes them to `/app/plan.txt`, one line per row. Each row's detail text appears on its own line.

Run `/app/plan.py` so that `/app/plan.txt` is produced.

The verifier checks that `/app/plan.txt` contains the plan detail line that proves the query is answered using the `idx_orders_customer` index (the line contains the text `SEARCH` and the index name `idx_orders_customer`), rather than a full table scan (`SCAN`).

Note: `sqlite3` ships in the standard library; no third-party packages are needed.