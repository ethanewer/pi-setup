# Copper Vane Freight — salvage a truncated manifest database

The Copper Vane freight line keeps its crate manifests in a SQLite database,
`manifest.db`. The only surviving copy was **truncated**: the file was cut
short, so part of its data is simply gone. Your job is to diagnose exactly how
the file was cut, salvage every intact row by parsing the surviving bytes, and
serialize the result to a schema-exact JSON report.

You work only inside `/app`. Python 3.12 (standard library only) is available.
Do not modify `/app/manifest.db`.

## The table schema (fixed, used by every fixture)

```sql
CREATE TABLE manifest (
  id         INTEGER PRIMARY KEY,
  crate      TEXT NOT NULL,
  origin     TEXT NOT NULL,
  weighed_on TEXT NOT NULL,
  mass       REAL NOT NULL
);
```

Because `id` is an `INTEGER PRIMARY KEY` (a rowid alias), it is stored as NULL
inside each record; its real value is the cell's **rowid**.

Guaranteed layout facts (you may rely on all of them):

- The database page size is the value stored big-endian in the file header at
  offset 16–17 (the value `1` there means 65536).
- Page 1 of the file is a **leaf table b-tree page** holding the
  `sqlite_schema` table, one row per schema object. Each schema record has the
  columns `(type TEXT, name TEXT, tbl_name TEXT, rootpage INTEGER, sql TEXT)`.
  The root page number of the `manifest` table is found by decoding the schema
  row whose `type` is `'table'` and `name` is `'manifest'`.
- The `manifest` root page is a **leaf table b-tree page** (type byte `0x0D`)
  holding all rows; there are no interior pages and no overflow pages
  (every payload fits inside its cell).

## SQLite on-disk formats you must decode

- **Leaf table b-tree page header** (at offset 0 of the page, or offset 100
  for page 1): byte 0 = page type (`0x0D` = leaf table), bytes 3–4 big-endian
  = number of cells, then (from header offset 8) a cell pointer array: one
  big-endian u16 per cell, each an offset **relative to the start of the page**.
- **Cell** (leaf table): a varint payload length, a varint rowid, then the
  record payload. A row is **intact** iff its entire payload lies within the
  retained bytes (cell start + varints + payload length ≤ retained file size).
  A cell whose payload runs past the cut is lost — skip it.
- **Varint**: 1–9 bytes, big-endian, 7 bits per byte with the high bit as
  continuation flag (the 9th byte contributes all 8 bits).
- **Record**: a varint header size, then one varint serial type per column,
  then the body. Serial types you will encounter: `0` = NULL,
  `1..6` = big-endian signed integers of 1,2,3,4,6,8 bytes, `7` = 8-byte
  big-endian IEEE-754 float, `13+2n` (odd) = TEXT of `n` bytes.

## Deliverables (both required)

1. `/app/salvage.py` — a runnable Python program:
   ```
   python3 /app/salvage.py <db_file> <output_json>
   ```
   It reads the (possibly truncated) database file and writes the salvage
   report JSON to the output path. It must work on **any** input file that
   follows the layout above, not just the provided fixture.

2. `/app/salvaged.json` — the report produced by running your program on the
   provided fixture:
   ```
   python3 /app/salvage.py /app/manifest.db /app/salvaged.json
   ```

## Report format (schema-exact)

```json
{
  "diagnosis": {
    "mode": "<string>",
    "page_size": <int>,
    "declared_pages": <int>,
    "retained_pages": <int>,
    "intact_rows": <int>
  },
  "salvaged": [
    {"id": 1, "crate": "CR-901", "origin": "Oslo",
     "weighed_on": "2043-03-14", "mass": 512.25}
  ]
}
```

- `page_size` — big-endian u16 at header offset 16 (with the `1 → 65536`
  special case).
- `declared_pages` — big-endian u32 at header offset 28 (the page count the
  header *claims*; it reflects the pre-truncation file). `0` if fewer than 32
  bytes were retained.
- `retained_pages` — `retained_bytes // page_size` (`0` if the header is too
  short to yield a page size).
- `mode` — the truncation mode, decided by these rules **in order**:
  1. `retained_bytes >= declared_pages * page_size` (and both are nonzero)
     → `"intact"`;
  2. `retained_bytes < 100` (the 100-byte file header is not even present)
     → `"empty"`;
  3. `retained_bytes` is an exact multiple of `page_size` →
     `"page-aligned-truncation"` (whole pages were cut off);
  4. otherwise → `"mid-page-truncation"` (the cut falls inside a page, so the
     last surviving page may be only partially present).
- `salvaged` — every intact row, **sorted by `id` ascending**. `id` comes from
  the cell rowid; `mass` is the IEEE-754 float; text fields are decoded as
  UTF-8/ASCII. `intact_rows` equals `len(salvaged)`.

An empty `salvaged` array is legal (e.g. when nothing survived).

## Grading / hidden inputs

The grader runs `/app/salvage.py` unchanged on the shipped `/app/manifest.db`
**and** on several hidden truncated databases with the same schema but
different sizes, data, row counts, and cut points — covering all four modes
(`intact`, `page-aligned-truncation`, `mid-page-truncation`, `empty`), cuts
that land inside a cell payload, and files whose schema page itself did not
survive. Both `diagnosis` and `salvaged` must be exactly right in every case
(floats compared to 6 decimal places). Do not hard-code row counts, modes, or
offsets; compute everything from the bytes.

## Constraints

- Work only under `/app`. Do not modify `/app/manifest.db`.
- Standard library only; no network access.
- Never read `/tests` — it is not present while you work.
