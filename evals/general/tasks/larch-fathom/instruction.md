# larch-fathom: stand up a live Postgres data tier for the Hopper data team

The Hopper data team needs a local Postgres service stood up from nothing, a
`customers` table created to a prescribed schema, messy contact data cleaned
entirely inside the database, an authentication query demonstrated to be
bypassable by a crafted SQL-injection payload, and Python bindings generated
from a `.proto` RPC definition.

Write **one** Python program, `/app/solve.py`, plus produce its output report
`/app/answer.json`. The program is a *reusable tool* driven entirely by command
line arguments, so the verifier can run your exact same `/app/solve.py` again on
fresh fixtures it mounts — different CSVs, a different proto, or a malformed
proto. It must not be a one-off hard-coded to the shipped files.

## Command line (the only inputs)

```
python3 /app/solve.py <DATA_CSV> <PROTO> <OUTDIR> <ANSWER_JSON>
```

| arg | meaning |
|---|---|
| `DATA_CSV` | messy customer rows, header line `full_name,email,phone,region` |
| `PROTO` | a proto3 `.proto` file describing an RPC service |
| `OUTDIR` | directory where generated Python bindings go |
| `ANSWER_JSON` | path where the JSON report is written |

Read **everything** from `sys.argv`. Do not hard-code the shipped fixture paths
(`/app/data/customers.csv`, `/app/proto/ledger.proto`) into the program.

## What the program must do

Proceed in this order within one run:

### 1. Bring the Postgres service up (no systemd)
If Postgres is not yet listening on `127.0.0.1:5432`, start it yourself. There is
**no systemd** in the container; the distro Postgres is supplied with
`/usr/lib/postgresql/<version>`. Use the distro cluster tooling, e.g.
`pg_lsclusters` / `pg_createcluster <version> main` / `pg_ctlcluster <version>
main start`, and wait until `pg_isready` reports ready. Provision an app role
and database, e.g. role `hopper` (LOGIN), password
`hopp3rXp12`, database `hopper` owned by that role, and grant the app role all
privileges on the database and on the `public` schema (plus default table
privileges), all executed over the superuser (`su postgres -c psql ...`) since
you are root.

Expose the live connection string at **`/app/database.env`**:
`export DATABASE_URL="postgresql://hopper:hopper_...@127.0.0.1:5432/hopper"`
(the exact credential string is yours to choose, but it must round-trip).

### 2. Create the prescribed `customers` table
```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    region TEXT
);
```

### 3. Load the data
Read `DATA_CSV`. The header row is `full_name,email,phone,region`. Treat a row
missing trailing fields as empty for those fields; ignore fully blank lines.
Escape quotes/backslashes for SQL. Load every parsed row into the `customers`
table. Write the exact `INSERT` statements you executed to **`/app/load.sql`**
(evidence).

### 4. Clean the data entirely in SQL (in-database)
Run these transformations **as SQL against the database** (not in Python), and
persist the statements executed to **`/app/clean.sql`**:
- lower-case and trim the `email` column;
- extract digits only into `phone`;
- remove exact duplicates on the pair `(email, phone)` keeping the earliest row;
- delete rows whose `email` **and** `phone` are both empty after cleaning.

### 5. Authentication bypass
Create a `users` table (`id`, `username` UNIQUE, `password`, `role`) containing
an `admin` row whose role is `administrator` and at least one non-privileged
analyst row. A naive login handler builds its query by concatenating the
credential strings:
`SELECT role FROM users WHERE username='<u>' AND password='<p>';`.
Craft a payload in the **username** field that defeats the check (e.g. a
tautology plus a comment ) and run the forged query yourself, confirming it
resolves to `administrator`. This is your deliverable, not a suggestion.

### 6. Generate Python bindings
From `PROTO`, generate the two Python binding modules
`<basename>_pb2.py` and `<basename>_pb2_grpc.py` into `OUTDIR`, e.g. with
`python3 -m grpc_tools.protoc -I<dir> --python_out=OUTDIR --grpc_python_out=OUTDIR file.proto`.
They must import and the generated message/service must be usable.

## The report (`ANSWER_JSON`)
A JSON object with **exactly** these keys:

```json
{
  "schema": ["full_name", "email", "phone", "region"],
  "target_role": "administrator",
  "forged_role": "administrator",
  "bypass_worked": true,
  "username": "<your injection username>",
  "password": "<your password field>",
  "forged_sql": "SELECT role FROM users WHERE ...",
  "total": 10,
  "cleaned": 8,
  "modules": ["ledger_pb2.py", "ledger_pb2_grpc.py"],
  "importable": true,
  "database_url": "postgresql://hopper:...@127.0.0.1:5432/hopper"
}
```

- `total` — number of parsed rows loaded.
- `cleaned` — number of rows in `customers` after step 4.
- `forged_role` — the role the forged query actually returns.
- `bypass_worked` — true iff `forged_role == target_role`.
- `modules` — the two generated filenames.
- `importable` — true iff both generated files exist.
- `database_url` / `schema` — as above.

## Expectations the verifier enforces
- `/app/answer.json` exists and its keys match the above.
- `total`, `cleaned`, `schema` are correct for the current `DATA_CSV`.
- the actual `customers` rows **in the running database** match an independent
  re-computation of the cleaning rules applied to `DATA_CSV`.
- a live connection via `DATABASE_URL` works; schema matches.
- the forged SQL injection actually authenticates as `administrator`.
- `load.sql` and `clean.sql` exist and contain the SQL evidence of those
  transformations.
- bindings are generated in `OUTDIR`, import, and expose the service/messages.
- the program generalizes: the same `/app/solve.py` must run correctly on fresh
  CSVs and protos (see below).

## Fresh hidden input kinds (so build it generic)
The verifier re-runs `/app/solve.py` unchanged against new fixtures:
- CSVs with different data, plus **edge cases**: a row whose quoted `full_name`
  contains a comma, an embedded apostrophe in either text column, rows missing
  one or both contact fields, rows that fully duplicate earlier ones (must
  collapse), and blank/trailing lines.
- protos with **different package/service/message/filename** (including `stream`
  RPCs, `enum`, `oneof`). Your generator must react to whatever proto it is
  given.
- a **malformed proto**: your program must detect the malformed definition and
  exit **non-zero** without writing binding modules. Handle this gracefully
  with a clear error.

## Constraints
- Only the shipped packages: Python 3 stdlib plus `psycopg` is not available; use
  `psql` via `subprocess` for SQL, `csv` for parsing, `grpc_tools.protoc` for
  codegen (`grpcio`, `grpcio-tools`, `protobuf` are installed).
- Do not modify `/app/data/customers.csv` or `/app/proto/ledger.proto`.
- Keep the program deterministic and idempotent (re-runs drop/recreate tables).

## Deliverables
- `/app/solve.py` — the reusable program.
- `/app/answer.json` — produced by running
  `python3 /app/solve.py /app/data/customers.csv /app/proto/ledger.proto /app/generated /app/answer.json`.