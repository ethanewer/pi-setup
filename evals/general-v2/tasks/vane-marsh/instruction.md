# Halden Grid — export meter readings from the metering service

Halden Grid operates a small metering platform. A PostgreSQL "meter store" is
already running **inside this container** and matches the service declared in
the compose-style stack file you were given:

- `/app/grid/compose.yaml` — describes the `meters` service: its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and the published
  `ports` entry (`"HOSTPORT:CONTAINERPORT"`).

The instance is reachable on **`127.0.0.1`** at the **host port published in
the compose file** (do not assume `5432`, the default port, the default
database, or any credential you have seen elsewhere — everything must come
from the compose file you are handed at run time).

The metering schema (table `meter_readings`) is:

```sql
CREATE TABLE meter_readings (
    id           serial PRIMARY KEY,
    meter        text NOT NULL,
    kwh          numeric NOT NULL,
    reading_date date NOT NULL,
    logged_at    timestamptz NOT NULL DEFAULT now()
);
```

## Your job

Build a **reusable export program** and use it to produce the report for the
provided stack. The program must derive its connection settings **only from
the compose file it is given** (host `127.0.0.1`, host port, database, user,
password). The verifier will run your program against the visible service and
against additional hidden metering instances whose compose files use
**different database names, users, passwords, and credentials quoting** — a
program that hard-codes the visible credentials or the default port will fail.

Do **not** modify the database (no inserts, updates, deletes, no DDL) and do
**not** modify `/app/grid/compose.yaml`.

## Deliverables (both required)

1. `/app/export.py` — a runnable Python 3 program with this interface:

   ```
   python3 /app/export.py <compose_file> <output_json>
   ```

   It must parse the compose-style file (documented shape below), connect to
   the described PostgreSQL instance, and write the report described below to
   the given output path. It must work on **any** compose file and database
   conforming to this contract, not only the provided fixture.

2. `/app/report.json` — the report your program produces **for the provided
   `/app/grid/compose.yaml`**:
   ```
   python3 /app/export.py /app/grid/compose.yaml /app/report.json
   ```

## Compose file contract

The input file is YAML-shaped exactly like the fixture: a top-level
`services:` mapping containing a service named `meters`, whose `environment`
mapping defines the keys `POSTGRES_DB`, `POSTGRES_USER`, and
`POSTGRES_PASSWORD` (scalar values, possibly double-quoted), and whose `ports`
list contains one entry of the form `"HOSTPORT:CONTAINERPORT"`. Read the
values with whitespace-tolerant parsing; handle surrounding double quotes.

## Required output JSON

The output file must be valid JSON with **exactly these keys**:

```json
{
  "database": "<POSTGRES_DB from the compose file>",
  "user": "<POSTGRES_USER from the compose file>",
  "row_count": <int>,
  "readings": [
    {"meter": "<text>", "kwh": <float>, "reading_date": "YYYY-MM-DD"},
    ...
  ]
}
```

- `readings` contains **every row currently in `meter_readings`**, with
  `kwh` as a JSON number (float) and `reading_date` as its plain
  `YYYY-MM-DD` text form.
- The list is sorted by `(meter, reading_date, kwh)` ascending.
- `row_count` equals the number of entries in `readings`.
- An **empty table** yields `"readings": []` and `"row_count": 0` (and the
  `database`/`user` keys still filled in from the compose file).

## Edge cases the grader probes on hidden inputs

- A different compose file with a different `POSTGRES_DB`, `POSTGRES_USER`,
  and `POSTGRES_PASSWORD` (and quoted/unquoted values).
- The published host port is **not** `5432` — derive it from `ports`
  (`"5433:5432"`-style); connecting to the default port must fail.
- Tables with **zero rows**, a **single row**, and many rows.
- Fractional `kwh` values (e.g. `13.875`) must round-trip exactly as floats.
- Never assume the database name is the user name or any fixed value.

## Constraints

- The verifier runs `/app/export.py` unchanged (via `python3`) on hidden
  compose/database pairs, so do not hard-code visible values.
- A running local PostgreSQL instance is provided (it is the one the compose
  file describes) and the `psql` client is installed. Standard library only
  for Python; calling the installed `psql` client from your program is fine.
- No network access beyond the local database connection.
- Verifier timeout: 300 seconds total.
