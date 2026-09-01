# Pumice Berth — bulk-load field telemetry through the client copy command

The volcano-monitoring network at Pumice Berth ships its sensor telemetry as a
flat CSV file. Your job is to build a reusable loader program that bulk-imports
the CSV into a SQLite database **through the SQLite client-side COPY facility**
(the `sqlite3` command-line client's `.import` dot-command) and emits a summary.
The load must be visible on the server side of a database file under the
required table.

## Environment

- Working directory: `/app`. It already contains the visible scenario files
  `/app/readings.csv` and `/app/schema.sql`. Python 3.12 and the SQLite
  command-line client `sqlite3` are installed.
- **Do not modify `/app/readings.csv` or `/app/schema.sql`.**

## Deliverables (all required)

1. `/app/solve.py` — a runnable Python program with this interface:
   ```
   python3 /app/solve.py <input_dir> <output_dir>
   ```
   `<input_dir>` contains `readings.csv` and `schema.sql` (the delivered task
   uses `/app` for both). It must write the three artifacts below into
   `<output_dir>`. It must work on **any** scenario directory conforming to the
   formats below — the grader runs it unchanged on hidden scenario directories.

2. `/app/loaded.db` — produced by running your solver on `/app`:
   a SQLite database whose `readings` table holds **every** CSV row with
   correct types (`id`/`value` stored as INTEGER/REAL, not TEXT).

3. `/app/import_log.txt` — produced by the same run: a transcript proving the
   CSV went through the **client-side copy** command.

4. `/app/summary.json` — produced by the same run (format below).

So the grader-visible run is exactly:
```
python3 /app/solve.py /app /app
```

## Input formats

`schema.sql` contains exactly this `CREATE TABLE` (it may be executed as-is):

```sql
CREATE TABLE readings (
  id          INTEGER PRIMARY KEY,
  sensor      TEXT    NOT NULL,
  metric      TEXT    NOT NULL,
  value       REAL    NOT NULL,
  recorded_on TEXT    NOT NULL
);
```

`readings.csv` has the header line `id,sensor,metric,value,recorded_on`
followed by one comma-separated record per line (no quotes, no empty rows).
`id` is a unique positive integer, `value` is a decimal number, `recorded_on`
is an ISO date `YYYY-MM-DD`.

## Required behavior

### 1. Client-side COPY bulk load

Load the CSV **through the SQLite client copy facility**: the `sqlite3`
command-line client's `.import` dot-command (run against a scratch staging
table inside `loaded.db`), then transfer the staged rows into the target
`readings` table with the correct column types. Do **not** hand-write INSERT
loops over the raw file — the load must genuinely go through the client copy
command.

### 2. `import_log.txt` — the evidence

Write a human-readable transcript of the client-side copy session. It must
contain, at minimum:

- the literal dot-command line `.import` (the client COPY statement),
- the CSV file name `readings.csv` and the staging table name,
- a final line `loaded_rows: <N>` where `<N>` is the number of rows landed in
  the `readings` table.

A log that lacks the `.import` statement evidence fails the check even if the
database contents are correct — the point of this task is that the load
happened through the client copy command.

### 3. `summary.json` — aggregates over the loaded table

Compute from the **loaded database** (not from re-reading the CSV) and write:

```json
{
  "total_rows": <int>,
  "by_metric": { "<metric>": <int count>, ... },
  "avg_value_by_metric": { "<metric>": <float>, ... },
  "min_recorded_on": "YYYY-MM-DD",
  "max_recorded_on": "YYYY-MM-DD"
}
```

- `by_metric` has one entry per distinct `metric` in the loaded table.
- `avg_value_by_metric` has exactly the same keys as `by_metric`; values are
  the arithmetic mean of `value` per metric (float).
- `min_recorded_on` / `max_recorded_on` are the lexicographic min/max ISO
  dates in the loaded table.

## Automatic grading / hidden inputs

The grader executes `/app/solve.py` on the shipped scenario (`/app` → `/app`)
and on several hidden scenario directories (same file layout, different data;
read-only input dir, writable output dir), and checks that:
- `loaded.db` is a valid SQLite database whose `readings` table equals the
  expected row set with correct types;
- `summary.json` equals the expected aggregates;
- `import_log.txt` contains the `.import` client-copy statement evidence and
  the correct `loaded_rows:` count.

## Constraints

- Work only under `/app` for the delivered task; do not modify the input
  files in any scenario directory.
- Never read `/tests` — it does not exist / is not mounted while you work.
- Standard library plus the `sqlite3` CLI only; no network access.
- Leave `/app/solve.py`, `/app/loaded.db`, `/app/import_log.txt`, and
  `/app/summary.json` in `/app`.
