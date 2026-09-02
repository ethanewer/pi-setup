# Flint-Crest Observatory: reconstruct the consolidated survey catalog

The Flint-Crest Observatory keeps its astronomy survey observations in a single
SQLite catalog. The copys are in a fragile state: some data was never loaded,
some lives in a database file that was cut short ("truncated"), and some is
stuck in an un-applied Write-Ahead Log (WAL). Your job is to write one reusable
Python program that, given a *scenario directory*, reconstructs the complete
`catalog` table and produces every required artifact.

You work only inside `/app`. Do not touch anything outside `/app`. Anything you
write must be under `/app`.

---

## The catalog schema (must be reproduced exactly)

`schema.sql` must contain exactly this `CREATE TABLE`:

```sql
CREATE TABLE catalog (
  id          INTEGER PRIMARY KEY,
  domain      TEXT    NOT NULL,
  site        TEXT    NOT NULL,
  recorded_on TEXT    NOT NULL,
  reading     REAL    NOT NULL
);
```

Every row of every source has these five fields: a unique integer `id`, a
science `domain`, a survey `site` name, an ISO `recorded_on` date
(`YYYY-MM-DD`), and a numeric `reading`.

## The scenario directory and its input files

A scenario directory (for the delivered task this is `/app`) may contain any
subset of:

| file               | meaning                                                            |
|--------------------|--------------------------------------------------------------------|
| `catalog.csv`      | records to **bulk load** using the SQLite **client-side copy**      |
| `legacy.db`        | a **byte-truncated** SQLite database holding salvageable records    |
| `wal.db` (+`wal.db-wal`) | a database whose WAL holds records that must be **auto-replayed** |
| `ref.db`           | a read-only database that the rewritten query must run against      |
| `legacy_query.sql` | a *legacy* (non-SQLite dialect) query you must rewrite              |

`catalog.csv` has a header line `id,domain,site,recorded_on,reading` followed
by one comma-separated record per line (no quotes, no empty rows).

## Deliverables you must produce under `/app`

Run your program with:

```
python3 /app/solve.py <input_dir> <output_dir>
```

Both the delivered task (`/app` → `/app`) and, later, fresh *hidden* scenario
directories (read-only inputs, writable output dir) will be passed to it. It
must therefore produce **the same named files into `<output_dir>` for any
valid scenario input**:

1. `/app/schema.sql` – the exact `CREATE TABLE` above.
2. `/app/recovered.db` – a SQLite database containing one `catalog` table with
   the **complete merged** row set (see "build the consolidated catalog").
3. `/app/salvage.json` – JSON `{"diagnosis": {...}, "salvaged": [...]}`
   describing the truncation and listing the intact records you salvaged.
4. `/app/summary.sql` – the aggregate/domain query (see "summary").
5. `/app/fixed_query.sql` – the SQLite-valid rewrite of `legacy_query.sql`.
6. `/app/import_log.txt` – a human-readable transcript proving the bulk CSV
   load went through the **client-side COPY** facility (see below).

## Build the consolidated catalog (the core work)

Create `recovered.db` with the schema above, then bring in every record:

1. **Client-side COPY load** `catalog.csv`. Use the SQLite **client copy**
   facility (the `sqlite3` CLI dot-command `.import`, run against a scratch
   database) — not hand-written INSERT loops — so the load is genuinely a
   client COPY. Record the outcome in `import_log.txt`.

2. **Salvage `legacy.db`.** This file was truncated in the middle of its data
   pages. Recover the records whose pages are still wholly present by parsing
   the file directly (SQLite B-tree leaf pages, serial-type record decoding).
   Do **not** rely on SQLite opening it (it may refuse); read the bytes and
   walk the `catalog` table. Records stored in the truncated-away tail are
   lost. Write each intact record into `recovered.db`, and store the intact
   rows plus a short diagnosis (which portion remained intact vs. lost) in
   `salvage.json`:

   ```json
   {
     "diagnosis": { "source": "legacy.db", "intact_rows": 95,
                    "retained_bytes": 12288, "declared_pages": 4,
                    "page_size": 4096 },
     "salvaged": [
       { "id": 2001, "domain": "astronomy", "site": "Site1",
         "recorded_on": "2023-04-01", "reading": 1.5 }
     ]
   }
   ```

   Diagnosis keys may vary, but `intact_rows` and the `salvaged` array must be
   present and correct. A fully-lost `legacy.db` (every page gone) is legal and
   must yield an empty `salvaged` array.

3. **Replay the WAL.** `wal.db` + `wal.db-wal` form a WAL-mode database whose
   un-applied journal must be **auto-replayed** on open. SQLite needs a
   writable location to rebuild the shared-memory index, so first copy the WAL
   files into your scratch output area and open them from there; reading must
   yield the full merged set (baseline plus appended/updated records). Merge
   those records into `recovered.db`.

4. **Merge.** Insert every CSV, salvaged, and WAL record into `catalog`; ids
   never collide across sources (each source uses a distinct id band). The
   final `catalog` table is the complete consolidated record set.

## The summary query (`summary.sql`)

`summary.sql` must be the single query that:

- keeps only rows whose `domain` is one of `astronomy`, `physics`, or `geology`
  (drop every other domain — chemistry, meteorology, biology, ... — entirely);
- groups the survivors by `site`;
- keeps a site only when it contributed at least **two** allowed-domain rows
  (an aggregate count filter written with `HAVING` / a subquery);
- returns rows ordered by `site`.

Use this exact text for `summary.sql`:

```sql
SELECT site, COUNT(*) AS n
FROM catalog
WHERE domain IN ('astronomy','physics','geology')
GROUP BY site
HAVING COUNT(*) >= 2
ORDER BY site;
```

## Rewrite the legacy query (`fixed_query.sql`)

`legacy_query.sql` is written in a *legacy* SQL dialect that SQLite will not
parse. It only uses three kinds of non-SQLite tokens (there are no others in
the fixtures), which you must translate to SQLite-valid equivalents:

1. `OFFSET <m> ROWS FETCH NEXT <n> ROWS ONLY` → `LIMIT <n> OFFSET <m>`
2. `FETCH FIRST <n> ROWS ONLY` (or `FETCH NEXT <n> ROWS ONLY`) → `LIMIT <n>`
3. `expr::TYPE` (e.g. `col::INTEGER`, `COUNT(*)::NUMERIC`) → `CAST(expr AS TYPE)`

`fixed_query.sql` must be the transformed query. When run against `ref.db`
(e.g. `sqlite3 ref.db < fixed_query.sql`) it must parse and return exactly the
same result rows as its SQLite-valid equivalent. Leaving any `::`, `FETCH`,
or `OFFSET ... ROWS ...` token un-transformed makes it invalid. Keep the
query otherwise identical (same SELECT/WHERE/GROUP BY/ORDER BY).

## Automatic grading / hidden inputs

A grading harness executes `/app/solve.py` against several other hidden
scenario directories (same file layout, different data), in addition to the
shipped `/app`, and checks:
- `schema.sql` parses and equals the prescribed schema;
- `recovered.db` is a valid database whose `catalog` equals the expected merged
  set;
- `salvage.json` equals the expected intact rows (including empty on the
  fully-lost edge case);
- running `summary.sql` on `recovered.db` yields exactly the expected rows;
- running `fixed_query.sql` on the scenario's `ref.db` yields the expected rows;
- `import_log.txt` documents the client-side COPY bulk load.

Your program must therefore be fully general: same six outputs for any valid
scenario directory, hard - fail nothing when a source is small, empty, or
completely lost, or when the legacy query is different.

## Constraints

- Work only under `/app`. Leave `/app/solve.py` and all six outputs in `/app`.
- `/app/solve.py` must be executable and accept the two positional arguments
  `input_dir` and `output_dir` (yes, they may be the same, e.g. `/app`, but
  the hidden runs use a read-only `input_dir` and a writable `output_dir`).
- Do not modify, rename, or delete any input file in the input directory.
- Never read `/tests` — it does not exist/ is not mounted while you work.
- Strings: `domain`, `site` are plain ASCII text; `reading` is a decimal.

## Environment

- Python 3.12 with the `sqlite3` module, plus the SQLite `sqlite3` command-line
  client (for the client-side COPY `.import`).
- All task inputs in `/app`, all your outputs must land in `/app`.