# Larkfield Airshed — pull verified telemetry from the compose-declared service

You are the data steward for the **Larkfield Airshed** monitoring network. A
PostgreSQL telemetry service is already running inside this container, and the
only description of *how to reach it* is a compose-style stack file:

- `/app/airshed/compose.yaml` — declares the `telemetry` service, its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and the published port
  mapping.

You must **derive every connection setting from that file** (host, port,
database, user, password) and use it to open a working connection. Do not
assume defaults: the instance does **not** listen on the conventional port,
and its credentials are whatever the compose file says. The instance listens
on loopback (`127.0.0.1`), and password authentication (SCRAM) is enforced for
TCP connections — a wrong or missing password is rejected outright.

The database schema is:

```sql
CREATE TABLE readings (
    id          serial PRIMARY KEY,
    site        text NOT NULL,
    metric      text NOT NULL,
    value       double precision NOT NULL,
    tier        text NOT NULL,          -- e.g. 'verified', 'raw', 'pending'
    recorded_at timestamptz NOT NULL DEFAULT now()
);
```

## Deliverables (both required)

1. `/app/pull_readings.py` — a runnable Python program with this interface:
   ```
   python3 /app/pull_readings.py <compose_file> <output_csv>
   ```
   It must parse the given compose-style file, derive the connection settings
   from it, connect to the live Postgres service, and write a CSV of the
   verified rows to the given output path. It must work on **any** compose
   file that follows the documented format below — the grader runs it
   unchanged against hidden service descriptions with *different* ports (in
   different notations), *different* databases, users, and passwords, and
   *different* rows. A program that hard-codes any connection value will pass
   at most the first case and fail the rest.

2. `/app/verified.csv` — the CSV your program produces **when run on the
   provided `/app/airshed/compose.yaml`**:
   ```
   python3 /app/pull_readings.py /app/airshed/compose.yaml /app/verified.csv
   ```

## Compose parsing contract

The compose file is small and simple; you may parse it with any means (regex,
line scanning, or a YAML library). Every conforming file has exactly this
shape:

```yaml
services:
  <name>:
    image: postgres:16
    environment:
      POSTGRES_DB: <database>            # may be missing
      POSTGRES_USER: <user>
      POSTGRES_PASSWORD: <password>
    ports:
      - "<published>:5432"
```

Rules the program must implement:

- Environment values may be **unquoted, single-quoted, or double-quoted**
  (strip the quotes; do not strip them from the value body).
- `ports` contains exactly **one** entry. The container port is always
  `5432`; the entry may be written as `"<host>:5432"` or with an optional
  address prefix `"<ip>:<host>:5432"`. The program must connect to the
  **published host port** (the one bound on `127.0.0.1`), not the container
  port.
- `POSTGRES_DB` **may be absent**; then the database name equals
  `POSTGRES_USER` (the Postgres default).
- The host is always `127.0.0.1`.

## Required CSV output

Written to the given output path, UTF-8 text:

- Header line exactly: `site,metric,value`
- Then one line per row of `readings` with `tier = 'verified'`, **ordered by
  `id` ascending**, with the three columns `site,metric,value` in that order
  (the value written as a decimal number, e.g. `11.5`; any parseable float
  rendering is accepted — the grader compares numerically).
- If there are no verified rows, the output is just the header line.

Use a real database connection (e.g. the `psycopg2` module, which is
installed, or the `psql` client) — the rows must come from the live service.

## Edge cases the grader probes

- A compose file with a **different published-port notation**
  (`"<ip>:<host>:5432"`).
- A compose file **without `POSTGRES_DB`** (database = user name).
- **Different credentials and database names** — the program must actually
  derive them, or the connection is refused.
- **Zero verified rows** — output must be the header line only.
- Rows with other tiers (`raw`, `pending`) must never appear.

## Constraints

- Do **not** modify `/app/airshed/compose.yaml`.
- Do not modify the database contents (read-only work: no INSERT/UPDATE/DELETE
  on `readings`).
- The verifier runs your program unchanged (via
  `python3 /app/pull_readings.py`) on hidden compose files that follow the
  same contract, so do not hard-code to the provided file's contents.
- Standard library plus `psycopg2` (already installed); no network access
  except the local database connection.
