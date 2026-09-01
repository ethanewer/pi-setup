# Fernvale Observatory — compose-driven warehouse export

Fernvale Observatory runs its instrument-telemetry warehouse as a
compose-style stack. A PostgreSQL instance built **exactly** from the stack
description below is already running inside this container:

- `/app/warehouse/compose.yaml` — the compose-style stack description. It
  declares the `postgres` service and its `POSTGRES_DB`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD`, and published port mapping.

Derive your connection settings **from that file** (host, port, database,
user, password). Do not assume different values. The server enforces
password authentication (SCRAM), so a connection made with any wrong
credential simply fails; there is no fallback.

The warehouse schema is:

```sql
CREATE TABLE telemetry_readings (
    reading_id integer PRIMARY KEY,
    sensor_id  text NOT NULL,
    reading    integer NOT NULL,
    quality    text NOT NULL
);
```

## Deliverables (both required)

1. `/app/warehouse_dump.py` — a runnable Python 3 program with this
   interface:

   ```
   python3 /app/warehouse_dump.py <compose_file> <output_csv>
   ```

   It must parse the given compose file, derive the connection settings from
   it, connect to the PostgreSQL server, and write the full contents of the
   `telemetry_readings` table to `<output_csv>` in the CSV format specified
   below. It must work **on any compose file** that follows the contract
   below, not just the provided one.

2. `/app/telemetry.csv` — the CSV your program produces **when run on the
   provided `/app/warehouse/compose.yaml`**:

   ```
   python3 /app/warehouse_dump.py /app/warehouse/compose.yaml /app/telemetry.csv
   ```

## Compose-file contract

The input file is a YAML subset as written by ordinary hand-edited stacks:

- A top-level `services:` mapping of service name -> service mapping.
- A service's `image:` value may be quoted. The **database service** is the
  one whose image value starts with `postgres:` (e.g. `postgres:16`,
  `"postgres:16.4"`). There may be **other services** in the file (monitoring
  dashboards, admin panels, exporters) — ignore them even when they carry
  their own `environment:` blocks or `ports:` mappings; their values are
  decoys.
- The database service has an `environment:` mapping with scalar values:
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`. Values may be
  unquoted, single-quoted, or double-quoted; strip matching surrounding
  quotes. Values may contain spaces, `#`, and other punctuation.
- The database service has a `ports:` list with entries like
  `"127.0.0.1:5433:5432"` or `"5541:5432"`, each mapping
  `[host_ip:]host_port:container_port`. The server is reachable on
  `127.0.0.1` at the **host port** (the second-to-last `:`-separated field).
  Use exactly that port; it is not always 5432.

The PostgreSQL server itself is already running on loopback at the host port
the compose file publishes. Your program does not start any server.

## Output CSV format

Write exactly the result of

```sql
SELECT reading_id, sensor_id, reading, quality
  FROM telemetry_readings
 ORDER BY reading_id
```

as standard CSV **with a header line** — i.e. the byte-identical output of
`psql`'s `\copy (...) TO STDOUT WITH (FORMAT csv, HEADER true)`:
first line `reading_id,sensor_id,reading,quality`, then one line per row,
comma-separated, no quoting (the data never contains commas or quotes), rows
ordered by `reading_id`, final newline.

## Error handling

If the compose file cannot be parsed, lacks the required database service or
its keys, or the connection/authentication fails, the program must exit with
a **non-zero status**, print a diagnostic to stderr, write nothing to
stdout, and not leave a partial output file.

## Hidden-test behavior you should know about

The grader runs `/app/warehouse_dump.py` (unchanged) against **additional
compose files paired with additional live PostgreSQL instances** that follow
the same contract: different host ports, different database names, users and
passwords (including quoted values containing punctuation), tables with
different rows, and stacks containing decoy non-postgres services. A program
that hard-codes the visible port, credentials, or table contents will pass
only the first case and fail the others.

## Constraints

- `psql` (postgresql-client) is installed in the image; your program may
  invoke it or use any local client. Standard library plus the installed
  client tools only — no network access beyond loopback.
- Do not modify `/app/warehouse/compose.yaml` or the database contents
  (no inserts/updates/deletes; reads only).
- Do not rename or relocate `/app/warehouse/compose.yaml`.
