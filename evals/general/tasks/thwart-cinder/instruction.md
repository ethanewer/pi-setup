# Meridian Freight — make the Monthly Cost Report fast again

You are the data platform engineer for **Meridian Freight**, a logistics
operator. The company warehouses every service event and every trip leg in a
PostgreSQL 16 analytical store, and finance runs the **Monthly Cost Report**
from it on the first business day of each month. The report is correct — the
numbers finance signs off — but it has always been slow, and it gets slower as
the warehouse grows. Your job is to fix the warehouse so the report (and the
other monthly reports like it) run fast, without losing a single row.

## What is already on disk

- **PostgreSQL 16** server and client (`psql`, `pg_ctl`, `pg_isready`) are
  installed. No network access is available at trial time; everything lives in
  this image.
- **A stopped cluster** at `/srv/pgdata` (owned by the `postgres` OS user —
  start the server as that user, e.g. `su postgres -c ...`). It holds one
  database, **`analytics`**, fully loaded, ANALYZEd, and shut down cleanly.
- `/app/warehouse/schema.sql` — the authoritative schema.
- `/app/queries/original.sql` — the current production Monthly Cost Report
  (slow form). This file must remain **byte-for-byte unchanged** — the grader
  fingerprints it.
- `/app/queries/README.md` — operational notes.

### The connection contract

The cluster must accept connections at:

```
psql -h 127.0.0.1 -p 5433 -U postgres -d analytics
```

(trust auth on loopback, no password; database `analytics`.) Nothing is
listening there when you start.

### Schema

Two fact tables, no secondary indexes, no constraints beyond what is shown:

```sql
CREATE TABLE events (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer NOT NULL,
    region      text    NOT NULL,
    kind        text    NOT NULL,
    occurred_at timestamp NOT NULL,
    amount      numeric(14,2) NOT NULL,   -- service-event cost, in EUR
    note        text    NOT NULL DEFAULT ''
);

CREATE TABLE journeys (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id   integer NOT NULL,
    region      text    NOT NULL,
    kind        text    NOT NULL,
    occurred_at timestamp NOT NULL,
    distance_km numeric(10,2) NOT NULL,
    note        text    NOT NULL DEFAULT ''
);
```

`events` holds 2,000,000 rows and `journeys` 1,200,000, spread over
2024-01-01 … 2026-02-28 across many tenants/regions/kinds. The warehouse has
been ANALYZEd, so the planner has accurate statistics.

### The report shape

Every monthly report in this warehouse — the visible `original.sql` and the
ones the grader will run — follows one shape: it filters **exactly one tenant
and exactly one calendar month of `occurred_at`**, then groups by month and
splits the rows into aggregated buckets. That shape is the only thing that
matters for performance; the grader's hidden reports are the same shape over
either `events` or `journeys`, with different tenants, months and groupings.

## Deliverables (all four required)

1. **`/app/db/start.sh`** — an executable shell script that starts the
   `analytics` cluster from `/srv/pgdata` according to the connection
   contract above. It must be:
   - **idempotent** (safe to run again while the cluster is already up);
   - returned with exit status 0 **only once** `psql` connects as specified;
   - strictly a *start* script: no schema changes, no data changes, no
     migration step inside it. All structural change goes through the
     migrations below.

2. **`/app/db/migrate/forward.sql`** — the forward migration: everything the
   fixed monthly reports need, applied in one `psql -f` run. The grader
   applies it to the pristine warehouse, so it must not assume the structures
   exist yet. It must leave **every row** in both tables exactly as it found
   them.

3. **`/app/db/migrate/backward.sql`** — the backward migration: removes
   exactly what `forward.sql` added, so the warehouse is back to the pristine
   state. It must also leave every row untouched. The grader applies
   forward → backward → forward in one session and fingerprints the tables
   after every step: any row lost, added, or altered by either migration
   fails the task.

4. **`/app/queries/report.sql`** — your rewritten Monthly Cost Report:
   the same month/report as `original.sql` (tenant 17, June 2025, grouped by
   kind), producing **exactly the same rows, in the same order, with the same
   values**, but engineered to run far faster.

## How you are graded

The grader starts the warehouse with your `/app/db/start.sh`, then:

- applies forward, backward, forward, fingerprinting both tables after each
  step (rows and checksums must never change);
- after a forward step, runs `EXPLAIN` on **three hidden month-window
  reports** (the report shape above, over `events` and `journeys`) and
  requires an **index-based access plan** for each — a plan that reads the
  table through an index rather than scanning the whole table;
- after the backward step, requires the same hidden reports' plans to revert
  to sequential scans, proving the migrations are the thing doing the work;
- executes the hidden reports and your `report.sql` through `EXPLAIN
  (ANALYZE, TIMING)` and enforces a generous execution-time gate: each hidden
  report must finish quickly, and your `report.sql` must run at least **3
  times faster** than `original.sql` measured back-to-back on the same host
  (and under an absolute ceiling). Your `report.sql` is held to the same
  access-method standard as the hidden reports: the plan the grader sees for
  it must also read the `events` table through an index rather than a full
  scan. The rewritten report must therefore be a real query over the
  warehouse — a constant that returns the month's rows without reading the
  tables does not satisfy the contract.

Nothing else is graded. `original.sql`, `schema.sql`, and the shipped data are
fixed inputs; do not modify them. You may run anything you like against the
warehouse while you work — psql, `EXPLAIN`, scratch indexes you later drop —
it is your sandbox. What is graded is the state you leave behind: the four
deliverables above.