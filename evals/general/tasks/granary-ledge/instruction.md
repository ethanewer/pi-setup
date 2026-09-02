# Granary Ledge — low-stock inventory report

You work for **Granary Ledge Provisions**, a bulk pantry supplier. The
provisioning team wants an automated low-stock report driven straight off the
provisioned Postgres store. Everything lives in `/app`.

## What is running

A PostgreSQL instance is already up inside this container. It matches the
service declared in the compose-style stack file:

- `/app/deploy/stack.yml` — describes the stack. One of the declared services
  is the Postgres store; its `environment` block carries `POSTGRES_DB`,
  `POSTGRES_USER` and `POSTGRES_PASSWORD`, and its `ports` entry publishes the
  host port.

**Derive every connection setting from that file** — database name, user,
password, and the host port (the **left-hand side** of the port mapping). The
instance listens on `127.0.0.1` at that published host port (it is *not* the
default 5432, and future stack files may differ). Do not assume other values.

The schema of the provisioning database is:

```sql
CREATE TABLE items (
    sku           text PRIMARY KEY,
    name          text NOT NULL,
    stock         integer NOT NULL,
    reorder_point integer NOT NULL,
    price         numeric(10,2) NOT NULL
);
```

An item is **low-stock** when `stock < reorder_point` (strictly less;
`stock == reorder_point` is *not* low).

## Deliverables (both required)

1. `/app/inspect.py` — a runnable Python program with this interface:

   ```
   python3 /app/inspect.py <stack_file> <output_json>
   ```

   It must read the given compose-style stack file, work out which service is
   the Postgres store (the service whose `image` contains `postgres`), derive
   the connection settings from its `environment` (which may be written as a
   mapping or as a list of `KEY=VALUE` strings) and its `ports` mapping, open
   a live connection to the instance, and write the JSON report described
   below to the given output path. It must work on **any** stack file and
   database that follow this contract, not just the provided ones — do not
   hard-code the visible credentials, service name, database name, or port.

2. `/app/report.json` — the report your program produces **when run on the
   provided stack file**:

   ```
   python3 /app/inspect.py /app/deploy/stack.yml /app/report.json
   ```

## Report format

The output file must be valid JSON with exactly these keys:

```json
{
  "service": "<name of the compose service that is the Postgres store>",
  "database": "<database name taken from the stack file>",
  "low_stock": [
    {"sku": "...", "name": "...", "stock": 3, "reorder_point": 10}
  ],
  "restock_units": 7,
  "restock_value": 22.75
}
```

- `service` — the name (key under `services`) of the Postgres service in the
  stack file that was used.
- `database` — the value of `POSTGRES_DB` for that service.
- `low_stock` — every item with `stock < reorder_point`, one object per item
  with exactly the keys `sku`, `name`, `stock`, `reorder_point`, sorted by
  `sku` ascending. When nothing is low this is `[]`.
- `restock_units` — the total shortfall: sum of
  `reorder_point - stock` over the low-stock items (an integer; `0` when the
  list is empty).
- `restock_value` — the total restock cost: sum of
  `(reorder_point - stock) * price` over the low-stock items, as a float
  rounded to 2 decimal places (`0.0` when the list is empty).

## Hidden-test behavior you should know about

The grader runs `/app/inspect.py` unchanged against **additional stack files**
paired with **additional database instances** that reuse this exact `items`
schema. Those stacks differ in the service name, database name, user,
password, and data (including stacks with **zero** low-stock items, and stacks
whose `environment` uses the list style `- POSTGRES_DB=...` instead of a
mapping). A program that hard-codes the visible values will pass only the
provided stack and fail the rest.

## Constraints

- Do not modify `/app/deploy/stack.yml` or the contents of the database
  (read-only work: no inserts/updates/deletes, no DDL).
- `python3` is Python 3.12; `yaml` and `psycopg2` are preinstalled. No
  network access beyond the local database connection.
- The verifier runs your program unchanged on hidden inputs; keep the CLI
  contract above exact.
