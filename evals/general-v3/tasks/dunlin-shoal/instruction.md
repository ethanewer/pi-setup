# Larkspur Field Station — telemetry archive exporter

The field station runs a PostgreSQL **telemetry archive** for its sensor
buoys. The database instance is already running inside this container. How to
reach it is described **only** by the compose-style stack file:

- `/app/deploy/compose.yaml` — describes the `archive` service: its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and the **published**
  port under `ports:`.

Derive your connection settings **from that file**. The instance listens on
`127.0.0.1` at the published port declared in the compose file. Do not assume
different values — the credentials are not the well-known defaults, and the
published port is **not** 5432. (If the instance is not answering, an
idempotent control script `/opt/dunctl/dbctl.sh up` brings it up; treat it as
image infrastructure.)

The schema of the archive database is:

```sql
CREATE TABLE sensor_readings (
    id        serial PRIMARY KEY,
    station   text NOT NULL,
    metric    text NOT NULL,
    value     integer NOT NULL,
    taken_at  timestamptz NOT NULL DEFAULT now()
);
```

## Deliverables (both required)

1. `/app/export.py` — a runnable Python 3 program with this interface:

   ```
   python3 /app/export.py <compose_file> <output_json>
   ```

   It must:
   - parse the given compose-style file (structure as in
     `/app/deploy/compose.yaml`; a small hand-rolled parser is fine, the
     layout is a plain nested mapping and comments/blank lines may appear
     anywhere);
   - extract the `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
     environment values and the **published** port (the left-hand side of the
     `ports:` entry);
   - connect to `127.0.0.1` at the published port with those credentials
     (`psql` / `postgresql-client` is installed; use whatever client tooling
     you like, but the program must run with only what is in this container);
   - query the `sensor_readings` table and write a JSON snapshot to
     `<output_json>` (atomically creating the file only after the query
     succeeded);
   - on any connection failure (wrong credentials, unreachable port) exit
     with a **non-zero** status, print a diagnostic to stderr, and **not
     create** the output file.

   The snapshot JSON has exactly these keys:

   ```json
   {
     "database": "<POSTGRES_DB from the compose file>",
     "port": <published port as an integer>,
     "row_count": <number of rows exported>,
     "readings": [["<station>", "<metric>", <value>], ...]
   }
   ```

   `readings` lists **every** row of `sensor_readings` as
   `[station, metric, value]`, sorted by `station`, then `metric`, then
   `value`, then `id` (ascending, plain string/integer ordering).

2. `/app/snapshot.json` — the snapshot your program produces **when run
   against the live archive using the provided compose file**:

   ```
   python3 /app/export.py /app/deploy/compose.yaml /app/snapshot.json
   ```

## Hidden-test behavior you should know about

The grader will run your `/app/export.py` **unchanged** against several
*additional* stack files (same layout, different service name, database,
user, password, published port and rows — each backed by a live instance).
A program that hard-codes the visible database name, user, password or port
will fail the hidden instances. The grader also includes a stack file whose
declared port has nothing listening on it; in that case your program must
fail as described above (non-zero exit, no output file).

## Rules

- **Read-only database access.** Do not insert, update or delete any row,
  and do not create or drop any table, database or role. The verifier
  compares row counts against the pristine seed.
- **Do not modify** `/app/deploy/compose.yaml`.
- No network access beyond the local database; standard library plus the
  tools already installed in the container only.
- The verifier runs your program with a timeout per invocation; keep it
  simple and fast.
