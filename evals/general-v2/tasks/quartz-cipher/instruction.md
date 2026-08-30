# Wardhaven Harbor — WAL durability audit (quartz-cipher)

You are working for **Wardhaven Harbor**, a freight forwarding yard. After a
power loss the operations team wants proof that recently committed shipping
records were **durably written to the Postgres write-ahead log (WAL)** and
survive a crash restart.

## What is running

A PostgreSQL instance is already up inside this container. It matches the
service declared in the compose-style stack file you were given:

- `/app/warehouse/compose.yaml` — describes the `store` service and its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and published `port`.

Derive your connection settings **from that file** (host, port, database,
user, password). Do not assume different values. The instance listens on
`127.0.0.1:5432`.

The schema in the `shipping` database is:

```sql
CREATE TABLE shipments (
    id          serial PRIMARY KEY,
    sku         text NOT NULL,
    qty         integer NOT NULL,
    destination text NOT NULL,
    batch       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
```

Most rows have `batch = 'seed'` and were checkpointed into the main heap.

A shipment batch tagged **`batch = 'wal-committed'`** was committed *after* the
last checkpoint, so those committed rows live in the WAL (`pg_wal`) rather than
in a checkpointed copy of the data. Reading a base snapshot alone (without the
WAL) would miss them; a proper client connection applies the pending WAL and
sees the true committed set.

## Your job (three deliverables)

You must **not** insert, update, or delete any row. Leave the database exactly
as you found it. Only create `/app/query.sql` and `/app/confirm.txt`.

1. **Connect** using the credentials in `/app/warehouse/compose.yaml`.

2. **Prove durability.** Verify with your own inspection that the committed
   `wal-committed` batch is genuinely durable. Use `pg_wal` inspection (for
   example the `pg_ls_waldir()` function) and/or a crash restart; after the
   restart the `wal-committed` rows must still be present. The point is that a
   plain dump taken before applying the WAL is *incomplete* — you must confirm
   the batch that was not checkpointed actually survives.

3. **Write /app/query.sql** — a *single SQL statement* — that, when run
   against the current database, returns **exactly** every
   `SHIPMENTS WHERE batch = 'wal-committed'` committed row, in column order
   `sku, qty, destination`. Do not return anything else (no `seed` rows, no
   extra columns, no rows you invented).

4. **Write /app/confirm.txt** — a short human-readable confirmation (any
   wording) that states the committed `wal-committed` batch is durable, i.e.
   survived crash recovery from the Postgres WAL. It must contain the string
   `wal-committed` and the word `durability` (or `durable`).

## query.sql strict format (the verifier enforces every rule)

If any of the following holds, the query is **rejected outright**:

- it is not exactly one statement;
- it contains any comment text (`--`, `/*`, `*/`) anywhere;
- it is missing the trailing semicolon, or contains extra semicolons;
- it does not start with `SELECT` or `WITH`;
- running it produces a result set that is not exactly the committed
  `wal-committed` rows compared above.

Whitespace, line breaks, indentation, upper/lower case, and a `WITH...` that
yields a single `SELECT` are all fine. Only one statement, no comments, one
final semicolon.

A correct example shape (your values must come from the real data; example
only, do not copy):

```sql
SELECT sku, qty, destination
  FROM shipments
 WHERE batch = 'wal-committed'
 ORDER BY sku;
```

Run `/app/query.sql` yourself with the derived connection and confirm it prints
exactly the durable rows before submitting.

What you must NOT do:
- do not modify or extend the database contents (no inserts, updates, deletes,
  no creating tables/views/roles);
- do not rename or relocate `/app/warehouse/compose.yaml`.

## Hidden-test behavior you should know about

The same `/app/query.sql` will later be executed against a few *additional*
database instances that reuse this exact schema and the same
`batch = 'wal-committed'` marker (different skus/destinations/counts). Your
query must therefore be written against the marker, not against the specific
sku values visible in the initial database. A query that hard-codes the visible
skus will pass only the first instance and fail the others.

Malformed `query.sql` variants (comments, extra semicolons, multi-statement
content, missing semicolon, non-`SELECT` opening) are all verified to be
rejected, so keep your file clean per the format rules above.

## Files you produce (leave at these exact paths)

- `/app/query.sql` — the single-statement query (format rules above).
- `/app/confirm.txt` — the durability confirmation text.

Only these two files will be examined. Everything else you do during the
session is your own working copy.