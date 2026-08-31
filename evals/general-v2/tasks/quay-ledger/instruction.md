# Quay Ledger — bulk-load the tide-gauge CSV via the client-side copy

The Quay harbor office keeps tide-gauge readings in a CSV extract that must be
brought into a SQLite database. You must write one reusable Python program that
loads the CSV into a prescribed table using the **client-side copy facility**
of the `sqlite3` command-line client — the `.import` dot-command — and records
the evidence of that load. Hand-written INSERT loops (e.g. reading the CSV in
Python and executing `INSERT` statements) do **not** satisfy the load
requirement: the load must genuinely go through the client copy command, and
the verifier checks the recorded statement evidence.

You work only inside `/app`. Do not touch anything outside `/app`.

## The prescribed schema (must be reproduced exactly)

The target table lives in the database you produce. Its `CREATE TABLE` is:

```sql
CREATE TABLE readings (
  station_id  INTEGER PRIMARY KEY,
  region      TEXT NOT NULL,
  observed_on TEXT NOT NULL,
  temp_c      REAL NOT NULL,
  humidity    REAL NOT NULL
);
```

Every CSV row has these five fields: an integer `station_id`, a text `region`
(which may contain commas, double quotes, and even line breaks — all properly
CSV-quoted), an ISO `observed_on` date (`YYYY-MM-DD`), a numeric `temp_c`, and
a numeric `humidity`.

## Deliverables (all required, all under `/app`)

Run your program with:

```
python3 /app/solve.py <input_dir> <output_dir>
```

The delivered task uses `/app` for both arguments, but hidden runs use a
read-only `<input_dir>` and a fresh writable `<output_dir>`. For any valid
scenario your program must produce, into `<output_dir>`:

1. `/app/solve.py` — the program itself (it must also be present at `/app`
   after the delivered run).
2. `loaded.db` (i.e. `/app/loaded.db`) — a SQLite database containing exactly the `readings` table
   above, populated with **every** CSV record from `<input_dir>/stations.csv`.
   The CSV has a header line `station_id,region,observed_on,temp_c,humidity`
   which must **not** be imported as a data row.
3. `/app/load_report.json` — JSON `{"rows_loaded": <int>, "regions": [...]}` where
   `rows_loaded` is the number of data rows now in `readings`, and `regions`
   is the alphabetically sorted list of the **distinct** `region` values as
   stored in the database.
4. `/app/import_log.txt` — a transcript of the client-side copy load. It must
   include the actual `.import` dot-command statement executed (with `.mode
   csv`), plus the row count loaded. A log that does not show the `.import`
   statement fails the statement-evidence check.

## How to load (the required method)

Run the `sqlite3` command-line client against the target database with a
script equivalent to:

```
CREATE TABLE readings (
  station_id  INTEGER PRIMARY KEY,
  region      TEXT NOT NULL,
  observed_on TEXT NOT NULL,
  temp_c      REAL NOT NULL,
  humidity    REAL NOT NULL
);
.mode csv
.import --csv --skip 1 "<absolute path to stations.csv>" readings
```

(If your `sqlite3` build lacks the `--skip` option, strip the header into a
temporary file first and `.import` that — the load must still go through
`.import`.) Quote-awareness is handled by `.mode csv`, so regions containing
commas, escaped double quotes, or embedded newlines import intact — do not
pre-split lines naively and do not hand-insert the rows.

## Edge cases the hidden scenarios probe

- Regions containing **commas** (`"Quay, East"`), **escaped double quotes**
  (`"Cliff ""Point"""`), and **embedded newlines** (a quoted region spanning
  two physical lines) — all must be stored exactly as decoded.
- Negative temperatures.
- A **header-only** CSV (zero data rows): `loaded.db` must have the empty
  `readings` table, `rows_loaded` 0, `regions` `[]`.
- A single-row CSV.
- `<output_dir>` different from `<input_dir>` (hidden runs); never modify or
  delete anything in `<input_dir>`.

## Automatic grading / hidden inputs

A grading harness executes `/app/solve.py` on the shipped `/app` scenario and
on several hidden scenario directories (same file layout, different data),
then checks for each:
- `loaded.db` is a valid database whose `readings` table has the prescribed
  schema (names, types, NOT NULL flags, primary key) and contains exactly the
  expected decoded rows;
- `load_report.json` reports the exact `rows_loaded` count and the sorted
  distinct `regions`;
- `import_log.txt` exists, is non-empty, and contains the `.import` client
  copy statement.

## Constraints

- Work only under `/app`; all outputs for the delivered run land in `/app`.
- `/app/solve.py` must accept the two positional arguments `input_dir` and
  `output_dir` (they may be the same, e.g. `/app`).
- Do not modify, rename, or delete any input file in the input directory.
- Never read `/tests` — it is not present while you work.
- No network access at verify time. Python 3.12 (`sqlite3` module) and the
  `sqlite3` CLI are installed.
