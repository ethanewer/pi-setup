# Item-069 (hard) — recover rows from a truncated SQLite database

`/app/ledger.db` is a **truncated** SQLite database. A media-forensics coworker
recovered the file after a failed storage copy; the trailing bytes were lost
mid-write. The declean and valid rows that survive are still in the file, but
SQLite reports the database as malformed (the on-disk pages do not line up with the
database-size field in the header). `/app/schema.sql` documents the original table
schema and tells you what was originally inserted.

Your job is forensic row recovery: recover **exactly** the `records` rows that are
still fully intact in the truncated binary, without fabricating any data.

## The original table

```
CREATE TABLE records (id INTEGER PRIMARY KEY, tag TEXT, amount REAL);
```

Rows were inserted with `id` = 1, 2, 3, ..., `tag` = `"tag_%04d"` (e.g.
`"tag_0001"`), and `amount` = `id * 1.5`.

## Important facts about the SQLite format

- The 100-byte database header starts at offset 0. Key fields:
  - offset 16 (2-byte BE): **page size** (`0x0200` here → 512).
  - offset 28 (4-byte BE): database **size in pages** — it was NOT rewritten when
    the file was cut, so it still describes the pre-truncation file. Trust the
    file's own length, not this stale field, when deciding how many pages remain.
- Every b-tree page has a header. For table pages the first byte's low nibble is
  the page type: `0x0d` = table **leaf**, `0x05` = table **internal**.
  Header layout: byte 0 = type; bytes 1-2 = first freeblock (0 = none); bytes 3-4 =
  number of cells; bytes 5-6 = start of cell content; byte 7 = fragmented bytes;
  for internal pages bytes 8-11 = rightmost child page number.
- Cell pointer array: for leaf pages it starts at byte 8 (byte 108 on page 1);
  for internal pages at byte 12 (byte 112 on page 1). Each entry is a 2-byte offset.
- A **table-leaf cell** at offset `O` is: `varint(C)`, then `varint(rowid)`, then
  the `C`-byte record. The record begins with a `varint(header_length)`, then one
  `varint` serial-type per column: type `0` = NULL; `1..6` = integer of that many
  bytes; `7` = IEEE 64-bit float; `8` = integer 0; `9` = integer 1; type `T >= 13
  odd` = text of `(T-13)/2` bytes.
- Work from a **copy** (`/app/copy.db`): keep `/app/ledger.db` byte-for-byte
  pristine. Read the pages from the copy and never mutate the original.

Recover by scanning every page present in the copy: any table-leaf page's cells
give you intact `records` rows. A row is only included if its entire cell content
falls within the file. Order the results by `id`.

## Deliverable

Write `/app/recovered.json`:

```json
{
  "recovered_rows": [
    {"id": 1, "tag": "tag_0001", "amount": 1.5},
    {"id": 2, "tag": "tag_0002", "amount": 3.0}
  ]
}
```

`recovered_rows` is sorted ascending by `id` and contains **every** intact row and
**nothing else**. Do not estimate, interpolate, or fabricate any row.

## Verification

The verifier independently re-parses `/app/ledger.db` for intact rows using the
same format rules, and requires your `recovered_rows` list to match exactly (same
rows, same values, sorted by `id`).