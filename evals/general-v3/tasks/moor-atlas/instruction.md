# Moor Atlas Survey — beacon registry census (moor-atlas)

You are the field-computing volunteer for the **Moor Atlas Survey**, a
peaty-hills beacon mapping project. The survey's beacon registry lives in a
PostgreSQL instance provisioned for this exercise. Everything you touch is
under `/app`.

## What is running

A PostgreSQL instance is already up inside this container. It matches the
service declared in the compose-style stack file:

- `/app/deploy/services.yml` — describes the stack. One of the declared
  services is the Postgres registry; its `environment` block carries
  `POSTGRES_DB`, `POSTGRES_USER` and `POSTGRES_PASSWORD`, and its `ports`
  entry publishes the host port.

**Derive every connection setting from that file** — database name, user,
password, and the host port (the **left-hand side** of the port mapping,
which is deliberately **not** 5432). The instance listens on `127.0.0.1` at
that published host port. Do not assume other values.

**Beware the decoy.** Another PostgreSQL instance is also running on this
box: a *retired* registry that kept the same database name and the same
credentials but whose `beacons` table is **empty**. The compose file is the
only source of truth for which instance is authoritative — a client pointed
at the wrong port connects "successfully" but reads an empty registry.

The schema of the authoritative registry database is:

```sql
CREATE TABLE beacons (
    beacon_id  serial PRIMARY KEY,
    code       text NOT NULL,
    grid       text NOT NULL,
    strength   integer NOT NULL,
    status     text NOT NULL,
    logged_at  timestamptz NOT NULL DEFAULT now()
);
```

`status` is one of `active`, `idle`, `offline`.

## Deliverables (both required)

1. `/app/audit.py` — a runnable Python program with this interface:

   ```
   python3 /app/audit.py <stack_file> <output_json>
   ```

   It must read the given compose-style stack file, work out which service is
   the Postgres registry (the service whose `image` contains `postgres`),
   derive the connection settings from its `environment` (which may be a
   mapping or a list of `KEY=VALUE` strings) and its `ports` list (entries
   like `"HOST:CONTAINER"`), open a **live** connection to
   `127.0.0.1:<host-port>` using exactly those credentials, and write the
   JSON audit described below to the given output path. It must work on
   **any** stack file and database that follow this contract — do not
   hard-code the visible credentials, service name, database name, or port.

2. `/app/audit.json` — the audit your program produces **when run on the
   provided stack file**:

   ```
   python3 /app/audit.py /app/deploy/services.yml /app/audit.json
   ```

## Audit format

The output file must be valid JSON with exactly these keys:

```json
{
  "database": "<database name taken from the stack file>",
  "user":     "<user name taken from the stack file>",
  "port":     <host port taken from the stack file, as an integer>,
  "beacons_total": <int, count of ALL rows in beacons>,
  "active":        <int, count of rows with status = 'active'>,
  "by_grid":       {"<grid>": <int, count of ACTIVE beacons on that grid>, ...},
  "strongest":     {"code": "...", "grid": "...", "strength": <int>} | null
}
```

- `database`, `user`, `port` are the values **derived from the stack file**.
- `by_grid` — one entry per grid that has at least one **active** beacon;
  grids with no active beacon do not create keys.
- `strongest` — the beacon with the highest `strength` (any status counts);
  on ties the beacon with the **lowest `beacon_id`** wins. When the table is
  empty this must be `null`.

## Failure behaviour (graded on hidden cases)

If the derived connection cannot be established — a wrong password, a port
nothing listens on, or an incomplete stack file — the program must:

- print a diagnostic to stderr,
- exit with a **non-zero** status,
- and **not create** the output file.

Do not swallow connection errors into an empty report.

## Hidden-test behavior you should know about

The grader runs `/app/audit.py` against a few *additional* stack files and
database scenarios that reuse this exact schema: different service names,
different databases/users/passwords, a stack file whose published port is a
**different listening instance**, a list-style `environment` block, an
**empty** registry, and stack files whose derived connection must **fail**
(bad password; unreachable port). Your program must therefore derive
everything from the stack file it is given — hard-coding the visible
credentials or port fails those cases.

## Constraints

- Do **not** modify `/app/deploy/services.yml` or anything inside the
  database (read-only access is enough for the audit).
- `PyYAML` and `psycopg2` are preinstalled in this image; no network access
  is needed at run/verify time other than the loopback database connection.
- Standard JSON, integers as integers, exact keys as listed.

## Files you produce (leave at these exact paths)

- `/app/audit.py` — the audit program.
- `/app/audit.json` — the audit for the visible stack file.
