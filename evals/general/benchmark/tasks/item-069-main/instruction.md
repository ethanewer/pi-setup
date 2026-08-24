# Recover rows from a truncated SQLite database by parsing its page format

## Context

`/app/data/corrupt.db` is a **truncated SQLite database** (a real SQLite file
that was cut short — its tail pages are missing). It once held a single table
`emp(id INTEGER PRIMARY KEY, name TEXT, salary INTEGER)` with 200 rows. Because
the file is truncated, SQLite itself refuses to open it (`database disk image
is malformed` — try it). But the rows still present in the surviving pages can
be recovered by **parsing the SQLite page format** directly.

Work on a **copy** (leave the original intact): e.g. `cp
/app/data/corrupt.db ./work.db` and parse the copy.

## The SQLite page format you need

- **Header** (first 100 bytes of page 1): bytes 16..17 (big-endian) are the
  page size (here 4096; a stored value of 1 means 65536).
- **Page roles**: page 1 is the `sqlite_master` b-tree (its content begins at
  byte **offset 100**, after the header). Pages are numbered from 1.
- **B-tree page fields** (relative to the page content start): byte 0 = type
  (13 = table *leaf*, 2 = table *internal*), bytes 3..4 = count of cells,
  bytes 8..9 = offset of first cell. For an internal node, byte 8..11 = first
  (leftmost) child page number, and **each cell starts with a 4-byte child
  page number**; for a leaf, each cell starts with a varint record-size, a
  varint row id, then the record payload.
- **Record layout** (leaf cell payload): a varint header-size, then one serial
  type byte per column, then the column values. For `emp` the stored columns
  are `name` (text) and `salary` (integer). The row **id** is the leaf cell's
  row-id varint (it IS the `id` column, an INTEGER PRIMARY KEY alias).
- Every row that can be physically reached (its leaf page number is within the
  truncated file) is recoverable; rows whose page is missing must be skipped.

## Your task

1. Copy the DB and parse page 1 to learn the page size and the root page
   (`rootpage`) of the `emp` table from `sqlite_master`.
2. Walk the `emp` B-tree (starting at its root page), recursing into child
   pages that lie fully inside the file. From each reachable leaf page, decode
   every row's id record.
3. **Recover exactly** the rows the file actually contains — do NOT fabricate
   ids that are not physically present, and do NOT drop rows that are.
4. Write `/app/recovered/recovered.json`:

   ```json
   { "recovered": [ <each row id, as an int, ascending>, ... ], "count": <n> }
   ```

## Success criteria

- `/app/recovered/recovered.json` exists, is valid JSON, and `count` equals the
  length of `recovered`.
- `recovered` contains **exactly** the set of rows physically present in the
  (truncated) file — no fabricated ids, no missing recoverable ids.