# Kelp Bastion: salvage rows from a byte-truncated SQLite ledger

The Kelp Bastion archive server died mid-write while compacting its accounting
ledger. The surviving file `/app/ledger.db` is a **byte-truncated SQLite
database**: the file header still declares the original page count, but the
tail of the file (some of its pages) is simply gone. SQLite itself may refuse
to open the damaged file, so you must recover the data **directly from the raw
bytes**.

Your job is to write a reusable recovery program that diagnoses the truncation
mode and salvages every ledger row whose storage page is still wholly present,
serialising them to a schema-exact JSON report.

Work only inside `/app`. Do not modify `/app/ledger.db`.

---

## The `ledger` table schema

The database contains a single table:

```sql
CREATE TABLE ledger (
  id        INTEGER PRIMARY KEY,
  account   TEXT NOT NULL,
  posted_on TEXT NOT NULL,
  amount    REAL NOT NULL,
  memo      TEXT NOT NULL
);
```

Every row has: an integer `id` (an alias for the SQLite **rowid**), a text
`account` (e.g. `ACC-1042`), an ISO date `posted_on` (`YYYY-MM-DD`), a numeric
`amount`, and a short text `memo`.

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:

   ```
   python3 /app/solve.py <db_file> <output_json>
   ```

   It reads the (possibly truncated) SQLite database at `<db_file>` and writes
   the recovery report to `<output_json>`. It must work on **any** input file
   that is a SQLite database holding this `ledger` table — intact or truncated
   — not just the provided file. Standard library only; no network.

2. `/app/recovered.json` — the report your program produces when run on the
   provided `/app/ledger.db`:

   ```
   python3 /app/solve.py /app/ledger.db /app/recovered.json
   ```

## Recovery strategy

Parse the file's bytes yourself (do not rely on the `sqlite3` library opening
the file — a truncated file may fail to open or silently return incomplete
results):

1. **Header.** The 100-byte file header holds the page size at offset 16
   (big-endian u16; the value `1` means 65536) and the declared page count at
   offset 28 (big-endian u32). Compare the declared size
   (`declared_pages * page_size`) with the actual file size to classify the
   file:
   - `"truncated"` — the file is smaller than the header declares;
   - `"intact"` — the file contains every declared page.

2. **Find the table root.** Page 1 holds the `sqlite_master` b-tree (its page
   header starts after the 100-byte file header). Decode its records — columns
   `(type, name, tbl_name, rootpage, sql)` — to locate the root page of
   `ledger`.

3. **Walk the table B-tree.** Table b-tree pages are either **interior** pages
   (type byte `0x05`: 4-byte child page numbers per cell plus a rightmost
   child pointer in the 12-byte header) or **leaf** pages (type byte `0x0d`:
   cells holding a payload-length varint, a rowid varint, and the record).
   A **cell pointer array** of 2-byte big-endian offsets follows each page
   header. Follow interior pages depth-first to every leaf.

4. **Salvage rule.** A page is salvageable only when it is **wholly present**
   in the file (its full `page_size` bytes are within the file). Rows living on
   a partially-present or absent page are **lost** — do not attempt to decode
   them. With small rows (as here) records never spill to overflow pages, so
   leaf cells can be decoded in place.

5. **Decode records.** A record is a header-length varint, a list of serial-type
   varints, then the value bytes. Serial types you must support: `0` = NULL,
   `1..6` = big-endian signed ints of 1/2/3/4/6/8 bytes, `7` = IEEE-754 float64,
   `8`/`9` = the constants 0/1, `>=13 odd` = UTF-8 text of `(N-13)/2` bytes.
   Note: the `id` column (INTEGER PRIMARY KEY) is stored as **NULL** in the
   record — its value is the cell's **rowid**. Also, SQLite stores an
   integral `REAL` (e.g. `5.0`) as an integer serial type; report such amounts
   as floats anyway.

## Required output JSON

The output file must be valid JSON with **exactly** these top-level keys:

```json
{
  "mode": "truncated",
  "page_size": 4096,
  "declared_pages": 6,
  "present_pages": 3,
  "lost_pages": 3,
  "salvaged_rows": [
    {"id": 1, "account": "ACC-1000", "posted_on": "2031-01-01",
     "amount": 5.0, "memo": "alpha"}
  ]
}
```

- `mode`: `"truncated"` or `"intact"` as classified above.
- `page_size`: the page size in bytes (offset 16; header value `1` means 65536).
- `declared_pages`: header page count (offset 28).
- `present_pages`: number of **whole** pages physically present, i.e.
  `floor(file_size / page_size)`.
- `lost_pages`: `max(0, declared_pages - present_pages)`.
- `salvaged_rows`: one object per intact row, **sorted by `id` ascending**,
  each with exactly the keys `id` (int, from the rowid), `account` (str),
  `posted_on` (str), `amount` (float), `memo` (str).

## Edge cases the grader's hidden inputs probe

The verifier runs your program unchanged on hidden databases covering:

- a fully **intact** database (mode `"intact"`, every row salvaged);
- a truncation that removes **all** table pages (only `sqlite_master` on
  page 1 survives → `salvaged_rows: []`, positive `lost_pages`);
- a **mid-page** truncation at a non-page-aligned byte offset (the partial
  final page is lost, earlier pages salvageable);
- an **empty** `ledger` table (zero rows → `salvaged_rows: []`, mode
  `"intact"`);
- a small page size (e.g. 512) that forces a **multi-level** B-tree with
  interior pages — the walk must recurse correctly;
- rows whose `amount` is integral and therefore stored as an integer serial
  type — they must still be reported as JSON floats (e.g. `5.0`).

Do not hard-code to the provided file's contents, page count, or row values.

## Constraints

- Work only under `/app`; leave `/app/solve.py` and `/app/recovered.json` there.
- Do not modify `/app/ledger.db` (the verifier checks its checksum).
- Python 3.12 standard library only; no network access.
