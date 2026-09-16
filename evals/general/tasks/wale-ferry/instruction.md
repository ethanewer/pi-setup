# Keel & Co. — restore the regional rollup workload

Keel & Co. runs a fulfillment analytics stack on **MariaDB 10.11**. The
operations team reads a set of weekly "regional sand status" rollups that
aggregate every order ever placed. Two weeks ago the reports started missing
their SLA: the queries take seconds instead of milliseconds, and `EXPLAIN`
shows the server sorting the whole table to build each group. A previous
engineer had sized the schema for *transactional* lookups — customer-level
fetches and status filters — and nobody has reviewed the analytical access
path since.

Nothing is running when you start. Your job is to diagnose against the live
server, fix the schema so the workload executes without full-table sorts, and
hand over the fix as a reusable migration plus a machine-readable diagnosis
record.

## Environment

- MariaDB 10.11.14 is installed (`mariadbd`, client `mariadb` — also linked
  as `mysql`). The data directory is initialised; **no server is running.**
- Bring the scenario up with the provided controller:

  ```
  /opt/warehouse/dbctl.sh up        # start + seed the pristine database (idempotent)
  /opt/warehouse/dbctl.sh ready     # exit 0 when the server answers
  /opt/warehouse/dbctl.sh stop      # clean shutdown
  /opt/warehouse/dbctl.sh reset     # restore the pristine state (drops the scenario db)
  /opt/warehouse/dbctl.sh status
  ```

  The first `up` seeds a ~1M-row dataset, so expect it to take up to a minute.
  Do **not** modify anything under `/opt/warehouse` — it is operational
  infrastructure, and resetting the database during your session is safe, but
  the controller files themselves must stay untouched.

- The server listens on the Unix socket `/run/mysqld/mysqld.sock` and on
  `127.0.0.1:3306`. The OS user is `root`, so the simplest access is:

  ```
  mariadb --socket=/run/mysqld/mysqld.sock analytics
  ```

  For TCP you may also log in as `analyst` with password
  `Dock-Side-Pass-2206` (password auth is enforced, so a wrong credential is
  refused; the `analyst` role has full privileges on the scenario database).

## What is on disk

| Path | What it is |
|---|---|
| `/app/schema/schema.sql` | authoritative DDL of the scenario — the live database is seeded identically to it |
| `/app/workload/q1_regional_status.sql` | report query 1 — regional × status rollup |
| `/app/workload/q2_online_partition.sql` | report query 2 — same rollup over online-channel orders |
| `/app/workload/q3_half_year.sql` | report query 3 — same rollup over the 2025-H1 window |
| `/app/workload/q4_three_dimensional.sql` | report query 4 — regional × status × channel rollup |

The database `analytics` contains the table `order_facts` (columns: `id`,
`customer_id`, `region`, `channel`, `status`, `placed_at`, `total`, `items`)
plus a dependent reporting view `vw_region_performance` that the ops team
reads directly. **Do not modify** any file under `/app/schema` or
`/app/workload`, and do not change the rows of `order_facts` (the workload
results are graded against a golden set).

`order_facts` currently carries the secondary indexes that were added for the
transactional access path. When you run the workload queries you will see the
symptom: `EXPLAIN` reports a full scan and `Using temporary; Using filesort`
(or `Using where; Using temporary; Using filesort`). The correct schema fix is
yours to derive — the reports' `GROUP BY`/`ORDER BY` and `WHERE` shapes and the
`EXPLAIN` output are the ground truth.

## Deliverables

1. **`/app/migration.sql`** — a single self-contained SQL script expressing
   your schema fix. Contract:

   - It must be **idempotent**: the verifier applies it twice in a row and the
     second application must succeed without error.
   - Applied to a freshly seeded (pristine) instance — via
     `mariadb analytics < /app/migration.sql`, i.e. it runs against the
     `analytics` database — it must make **every** workload query and every
     unseen variant of the workload family plan without a full-table sort.
   - It must not change, delete, or alter any data row, must not drop or
     change the definition of any table or of `vw_region_performance`, and
     must not change the columns or types of `order_facts`. Indexes on the
     table may be added, replaced, or removed.
   - Ordinary SQL only — no shell, no client configuration changes, no
     server options.

2. **`/app/explain_report.tsv`** — a diagnosis record of the plans your
   migration produces. Exactly four lines, one per workload query in the
   order q1, q2, q3, q4, each line

   ```
   q<N>	<select_type>	<type>	<key>	<Extra>
   ```

   where the last four fields are the 2nd, 4th, 6th and 10th tab-separated
   columns of the row that this command prints for that query:

   ```
   mariadb --batch --column-names=0 analytics \
     -e "EXPLAIN $(cat /app/workload/q<N>_<name>.sql)"
   ```

   Copy the values verbatim, including `NULL` when a field is null. The report
   must reflect the state **after** your migration is applied — no report, or
   a report that does not match the plans the verifier re-derives, scores 0.

## What the grader checks

The grader resets the database to its pristine seed, applies `/app/migration.sql`
**twice**, and then, for the four workload queries and three unseen queries of
the same family:

- re-derives `EXPLAIN` and asserts the plan uses an index key (no full table
  scan) with no `filesort` anywhere in `Extra` — and that the chosen key is
  ordered on the rollup dimensions of the workload;
- re-runs the query and compares the result rows byte-for-byte against the
  golden set;
- confirms `vw_region_performance` still resolves and returns exactly the rows
  it returns on the pristine data;
- compares its own re-derived EXPLAIN rows against your `/app/explain_report.tsv`.

So: the migration must fix the access path **generally** (the unseen queries
exercise different windows, partitions and grouping depths than the four
visible ones), must leave the data and the view untouched, and the report must
be honest.

## Constraints

- No network access; everything runs on this container.
- Work only against the live server via its SQL interface. Do not edit
  `/opt/warehouse`, `/app/schema`, `/app/workload`, or the files in
  `/app` other than creating the two deliverables.