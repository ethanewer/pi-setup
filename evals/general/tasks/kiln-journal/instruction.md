# Kiln telemetry — restore the recovered journal and merge it back

A kiln-monitoring service writes its `readings` table to a SQLite database in
**WAL (write-ahead log) mode**. During an incident the machine crashed, and a
backup process salvaged two artifacts into `/app`:

- `/app/telemetry.db` — the main database file. It contains only the rows that
  had already been checkpointed into it.
- `/app/journal/telemetry.wal` — the **recovered write-ahead log** holding every
  committed change that was never checkpointed: appended rows, `UPDATE`s to
  existing rows, and `DELETE`s.

SQLite automatically **replays** the journal when the database is opened — but
only if the WAL file sits beside the database file under its expected name
(`<dbfile>-wal`). Your job is to restore the journal and produce the merged
database.

## Deliverables (all under `/app`)

1. **`/app/solve.py`** — a reusable program:

   ```
   python3 /app/solve.py <input_dir> <output_dir>
   ```

   For an input directory containing `telemetry.db` and optionally
   `journal/telemetry.wal`, it must produce `<output_dir>/merged.db` and
   `<output_dir>/merged.json` (below). It must work on **any** scenario
   directory with this layout, including ones where the journal is absent.

2. **`/app/merged.db`** — produced by running your program on `/app` itself
   (`python3 /app/solve.py /app /app`). A valid SQLite database containing one
   table `readings` with the **complete merged record set**:

   ```sql
   CREATE TABLE readings (
     id        INTEGER PRIMARY KEY,
     sensor    TEXT NOT NULL,
     celsius   REAL NOT NULL,
     taken_on  TEXT NOT NULL
   );
   ```

   The merged set is: baseline rows from `telemetry.db`, **plus** every row
   appended in the journal, **with** every journal `UPDATE` applied (new values
   win) and every journal `DELETE` applied (those rows are gone).

3. **`/app/merged.json`** — a JSON summary of the merged set:

   ```json
   {"count": <int>, "rows": [["<id>", "<sensor>", "<celsius>", "<taken_on>"], ...]}
   ```

   where `rows` is ordered by ascending `id`, `celsius` is a JSON number and the
   other fields keep their stored types (id integer, sensor/taken_on strings).

## How to do the replay (the graded mechanism)

- Copy the database file and the recovered WAL into a **writable scratch area**:
  the database as `telemetry.db`, the journal as `telemetry.db-wal` **beside
  it**.
- Open the copy with SQLite (the `sqlite3` module or CLI). On open, SQLite
  recovers the WAL and replays every committed transaction, so a plain `SELECT
  id, sensor, celsius, taken_on FROM readings ORDER BY id` already returns the
  full merged set — baseline **plus** the journal's appended/updated/deleted
  state.
- Do **not** hand-parse the WAL format, and do not silently filter records out:
  every committed journal transaction must be reflected in the merged set.

## Edge cases the grader probes (hidden scenario directories)

- A journal with **appends only**.
- A journal with a **mix** of appends, `UPDATE`s and `DELETE`s.
- **No journal at all** (`journal/telemetry.wal` absent): the merged set is
  exactly the baseline rows.
- A journal with **many** committed appends.
- Ids are unique across baseline and journal; the final table must be the exact
  merged set ordered by `id`.

## Constraints

- **Never modify the input files.** The grader hashes `telemetry.db` and
  `journal/telemetry.wal` before and after your run and requires them
  byte-identical — do the replay on copies in the output/scratch area only.
- Python 3.12 standard library only (the `sqlite3` module and the `sqlite3`
  CLI are available); no network.
- Do not read `/tests` or `/solution`.
- When the journal is absent, your program must still succeed (baseline only).
