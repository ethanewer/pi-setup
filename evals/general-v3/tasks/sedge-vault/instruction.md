# Sedgevault Field Archive — specimen export via compose-provided credentials

You are the data steward for the **Sedgevault Field Archive**, a botanical
field-research trust. The archive's specimen database runs as a PostgreSQL
instance inside this container, described by a compose-style stack file:

- `/app/archive/stack.yaml` — describes the `specimen-db` service and its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and published `port`.

Derive your connection settings **from that file** (host, port, database,
user, password). Do not assume different values. The instance listens on
`127.0.0.1` at the **published** port (the first number of the `HOST:5432`
mapping), not necessarily on 5432. The server requires real password
authentication over TCP — a wrong user or password is rejected.

The schema in the archive database is:

```sql
CREATE TABLE specimens (
    id           serial PRIMARY KEY,
    catalog_code text NOT NULL,
    species      text NOT NULL,
    quadrant     text NOT NULL,
    collected_at date NOT NULL,
    mass_g       integer NOT NULL
);
```

## Your job (two deliverables)

You must **not** insert, update, or delete any row and must not modify the
database schema. Leave the database exactly as you found it.

1. **Write `/app/export.py`** — a runnable Python program with this interface:

   ```
   python3 /app/export.py <stack_file> <output_json>
   ```

   It must read the given compose-style stack file, **derive** the host,
   published port, database name, user, and password from it, connect to that
   Postgres instance, and write a JSON export of the `specimens` table to the
   given output path. It must work on **any** stack file that follows the
   documented format below, not just the provided one.

2. **Write `/app/specimens.json`** — the export your program produces **when
   run on the provided `/app/archive/stack.yaml`**:

   ```
   python3 /app/export.py /app/archive/stack.yaml /app/specimens.json
   ```

## Output format of the export

The output file must be valid JSON: a single **array** of objects, one per
row of `public.specimens`, **sorted by `id`** (ascending), each object with
exactly these five keys:

```json
[
  {"catalog_code": "SH-1041", "species": "Silene uniflora",
   "quadrant": "Q3", "collected_at": "2031-04-12", "mass_g": 214}
]
```

- `catalog_code`, `species`, `quadrant` — strings, verbatim from the table.
- `collected_at` — the date as an ISO `YYYY-MM-DD` string.
- `mass_g` — an integer.
- The `id` column itself is **not** included; ordering by `id` only defines
  the array order.

## Stack-file format your program must support

The stack file is a compose-style YAML subset:

- a top-level `services:` mapping; **exactly one** service declares a
  Postgres image (its `image:` value contains `postgres`) — other services
  may be present and must be ignored;
- that service has an `environment:` mapping with the keys `POSTGRES_DB`,
  `POSTGRES_USER`, `POSTGRES_PASSWORD` (values may be double-quoted or bare,
  and the keys may appear in any order);
- it has a `ports:` list with a single entry of the form
  `"PUBLISHED:5432"` (quotes optional); the published port is the first
  number;
- comment lines (`#`) and blank lines may appear anywhere;
- the Postgres instance itself always listens on host `127.0.0.1` at the
  published port.

## Hidden-test behavior you should know about

The verifier runs `/app/export.py` **unchanged** against a few *additional*
stack files describing other databases on the same live instance — with
different database names, different users and passwords, different row data,
and different formatting (extra unrelated services, unquoted values, comment
noise). A program that hard-codes the visible credentials, database name, or
port will pass only the first case and fail the others.

## Constraints

- Do not modify `/app/archive/stack.yaml` (the verifier checks its integrity).
- No network access at verify time other than the local loopback connection
  to the Postgres instance. The `psql` client is installed; you may shell out
  to it or use any locally available driver.
- Standard library plus the preinstalled tooling only; no pip installs at
  verify time.

## Files you produce (leave at these exact paths)

- `/app/export.py` — the credential-deriving export program.
- `/app/specimens.json` — the export for the provided stack file.

Only these two files are examined.
