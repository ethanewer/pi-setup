# Gullhaven Tide Observatory — connection report from the compose stack

You are the on-call data engineer for the **Gullhaven Tide Observatory**. The
observatory's temperature-gauge database runs inside this container as a
PostgreSQL instance. How to reach it is described **only** by the compose-style
stack file you were given:

- `/app/stack/compose.yaml` — describes the `tidedb` service and its
  `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and published `ports`.

Derive your connection settings **from that file** (host, host-side port,
database, user, password). Do not assume different values. The instance
listens on TCP with password authentication (scram), so a wrong password is
rejected — there is no trust fallback.

The database schema in the compose database is:

```sql
CREATE TABLE readings (
    id        serial PRIMARY KEY,
    station   text NOT NULL,
    celsius   numeric(6,2) NOT NULL,
    taken_at  timestamptz NOT NULL DEFAULT now()
);
```

## Your job (two deliverables)

1. **Write /app/fetch_report.py** — a runnable Python 3 program with this
   interface:

   ```
   python3 /app/fetch_report.py <compose_file> <output_json>
   ```

   It must:

   - Parse the given compose file and derive **all** connection facts from it
     (never hard-code them): host `127.0.0.1`; the **host-side** port from the
     `ports` mapping (an entry like `"127.0.0.1:5544:5432"` — the client port
     is the middle number; an entry like `"5544:5432"` means host port 5544 on
     `127.0.0.1`); `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` from the
     `environment` map (values may be quoted — strip surrounding quotes).
   - Connect to the Postgres instance over TCP using those credentials. You
     may use `psql` (available in the image) via `subprocess` with
     `PGPASSWORD`, or any client library present.
   - Run **exactly** this aggregation:

     ```sql
     SELECT station, count(*), avg(celsius), max(celsius)
       FROM readings
      GROUP BY station
      ORDER BY station;
     ```

   - Write the report JSON to the given output path with exactly these keys:

     ```json
     {
       "connection": {"host": "127.0.0.1", "port": <int>, "database": "<db>", "user": "<user>"},
       "stations":   {"<station>": {"readings": <int>, "avg_celsius": <float>, "max_celsius": <float>}},
       "total_readings": <int>
     }
     ```

     - one `stations` entry per distinct station present in `readings`;
     - `readings` = row count for that station, `avg_celsius` = average of
       `celsius`, `max_celsius` = maximum of `celsius` (plain floats);
     - `total_readings` = total row count (sum over stations);
     - the `connection` block must echo the derived host, port (as an
       integer), database, and user — never the password.

   - **Fail safely**: if the connection fails (wrong credentials, wrong port,
     unreachable database, missing table), exit **non-zero**, print nothing to
     stdout (a stderr message is fine), and **do not create** the output file.

2. **Write /app/report.json** — the report your program produces for the
   provided stack:

   ```
   python3 /app/fetch_report.py /app/stack/compose.yaml /app/report.json
   ```

   Run it yourself and confirm the JSON is correct before submitting.

## Constraints

- **Do not modify `/app/stack/compose.yaml`.** The verifier checks its
  checksum.
- The verifier runs your program **unchanged** on additional compose files
  that describe *other* databases: different database names, different roles
  with **different passwords**, and one scenario on a **different published
  port** (its own Postgres cluster). A program that hard-codes the visible
  credentials or port will fail those scenarios. The same report shape and the
  same aggregation query apply everywhere; the hidden databases all have the
  `readings` table with the schema above.
- The verifier also feeds a compose file with an intentionally **wrong
  password**: your program must fail safely there (non-zero exit, no output
  file created).
- No network access beyond the local Postgres connections; standard library
  plus `psql` only.
