# Chert Quay depot: salvage rows from a truncated SQLite scan database

The Chert Quay cold-chain depot records pallet weighings in a SQLite database
(`scan` table). The depot's snapshot job crashed halfway through copying the
database file, leaving a **byte-truncated** copy. Your job is to write one
reusable Python program that diagnoses *how* the file was truncated, salvages
every row that is still readable, and serializes them to a schema-exact JSON
report.

You work only inside `/app`. Do not touch anything outside `/app`. Anything
you write must live under `/app`.

---

## The `scan` table schema (fixed for all scenarios)

```sql
CREATE TABLE scan (
  id         INTEGER PRIMARY KEY,
  pallet     TEXT NOT NULL,
  lane       INTEGER NOT NULL,
  gross_kg   REAL NOT NULL,
  scanned_at TEXT NOT NULL
);
```

In every scenario the `id` values are the contiguous integers `1..N` (rows
were inserted in id order, nothing was ever deleted or updated).

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:

   ```
   python3 /app/solve.py <db_file> <output_json>
   ```

   It reads a (possibly truncated) SQLite database containing the `scan`
   table and writes the JSON report described below. It must work on **any**
   input file that follows this contract, not just the provided one.

2. `/app/salvaged.json` — the report your program produces **when run on the
   provided `/app/corrupt.db`**:

   ```
   python3 /app/solve.py /app/corrupt.db /app/salvaged.json
   ```

## Reading the SQLite header

The first 100 bytes of the file are the database header:

- bytes 16..17 (big-endian unsigned 16-bit): the page size in bytes; the
  value `1` means 65536. All scenarios use 4096, but read it from the header.
- bytes 28..31 (big-endian unsigned 32-bit): the header page count, i.e. how
  many pages the database had *before* truncation.
- bytes 0..15: the magic string `SQLite format 3\x00`.

## Truncation mode (diagnosis)

Let `file_bytes` be the actual size of the file, `page_size` and
`header_page_count` the two header fields, and
`present_page_count = file_bytes // page_size`. The output must classify the
file into exactly one of three modes:

- `"intact"` — `file_bytes >= header_page_count * page_size`: the file is not
  truncated at all.
- `"page_aligned"` — the file is shorter than the header claims **and**
  `file_bytes % page_size == 0`: whole pages were lost but no page is partial.
- `"mid_page"` — the file is shorter than the header claims and
  `file_bytes % page_size != 0`: the copy stopped in the middle of a page, so
  the final partial page is unusable as a page (although individual cells of
  that page may still be intact — see below).

`missing_bytes = max(0, header_page_count * page_size - file_bytes)`.

## Salvage semantics

A row counts as salvaged if and only if it is still readable after the file
is **padded with zero bytes to `header_page_count * page_size`** and opened
read-only. Concretely, a practical and exact recipe is:

1. Copy the file, pad it with `0x00` bytes up to
   `header_page_count * page_size` bytes (skip if already that large).
2. Open the padded copy with SQLite in read-only mode.
3. Probe row ids in ascending order starting at 1
   (`SELECT ... FROM scan WHERE id = ?`), one id at a time. If the query
   raises an SQLite error (e.g. "database disk image is malformed") or
   returns nothing, that id is lost. If it returns a row whose fields match
   the schema types (`id` int, `pallet` str, `lane` int, `gross_kg` int or
   float, `scanned_at` str), the row is salvaged.
4. Stop after 1000 consecutive lost ids (or 200000 probes).

Note that in a `mid_page` file some rows whose page is incomplete can still
be salvaged (their cell bytes lie entirely within the surviving bytes), while
others on the same partial page are lost. The recipe above handles this
automatically — do not simply drop the last `present_page_count`-th page.

## Required output JSON

The output file must be valid JSON with exactly this shape:

```json
{
  "file": {
    "page_size": <int>,
    "header_page_count": <int>,
    "present_page_count": <int>,
    "file_bytes": <int>
  },
  "truncation": {
    "mode": "<intact|page_aligned|mid_page>",
    "missing_bytes": <int>
  },
  "salvaged_rows": [
    {"id": <int>, "pallet": "<str>", "lane": <int>,
     "gross_kg": <float>, "scanned_at": "<str>"},
    ...
  ]
}
```

- `salvaged_rows` is ordered by ascending `id` and holds exactly the rows
  that pass the salvage test above.
- `gross_kg` must be serialized as a JSON number (float).

## Edge cases the grader probes (hidden inputs)

- A file that is **not truncated at all** (`mode = "intact"`, every row
  salvaged, `missing_bytes = 0`).
- A file truncated **exactly on a page boundary** (`mode = "page_aligned"`).
- Files truncated **mid-page** at various offsets (`mode = "mid_page"`),
  where only part of the final partial page's rows survive.
- Databases of different sizes (a few hundred to a couple thousand rows).
- The header page count always exceeds `present_page_count` for truncated
  inputs, and always matches the real size for intact inputs.

## Constraints

- The verifier runs your program **unchanged** (`python3 /app/solve.py`) on
  hidden database files that follow the same contract, so do not hard-code
  anything about the provided file (sizes, row contents, ids).
- Do not modify `/app/corrupt.db`.
- No network access at verify time; Python standard library only.
