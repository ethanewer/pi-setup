# Incident: recover the clinic's appointments from a XORed SQLite WAL

## Background

The clinic's "orders" database (SQLite, WAL journal mode) lost its most recent
batch of appointments. IT files a **read-only snapshot** right after the
incident. Every file under `/app/evidence/` is original forensic evidence and
must be treated as read-only.

Layout:

```
/app/evidence/
  orders.db        main database file (SQLite, WAL mode)
  orders.db-wal    write-ahead log — THIS file is damaged/corrupt
  incident.md      the incident note you are reading
  audit.csv        last known-good export (taken the day before the incident)
```

## What IT knows about the corruption

- The exporter that wrote `orders.db-wal` was recently modified. A code review
  found a bug in `wal_xor()`: it XORs every byte it wrote with one **fixed
  repeating byte** (a single XOR key, the same for the whole batch). The
  exporter XORed the frames it wrote but left the **32-byte WAL file header
  intact** (not XORed).
- The exporter only touched the `-wal` file; `orders.db` itself was not
  modified and still holds the 100 rows that were committed before that bad
  batch was written.
- A correct WAL for the same write batch, when applied to the DB, brings the
  table to **140 rows** total (100 baseline + 40 that were in the damaged WAL).

## Goal

Recover a database whose `orders` table has **exactly 140 rows**. Do the
following:

1. **Preserve evidence** — never write anything under `/app/evidence/`. Copy
   `orders.db` and `orders.db-wal` into a scratch working directory first.
2. **Infer the XOR key** from the bytes. A valid SQLite WAL consists of a 32
   byte file header followed by frames. Each frame has a 24-byte frame header;
   the first 4 bytes of frame #1 are the big-endian frame number `00 00 00 01`.
   Since the 32-byte file header was NOT XORed, decode the exposed frame
   headers and infer the single repeating XOR byte. Verify your inference by
   confirming that after XOR, EVERY frame header decodes consistently (valid
   frame number and page number fields, matching salt values from the header).
3. **Repair** a COPY of the WAL: XOR every byte from offset 32 to the end with
   the inferred key.
4. Place the repaired `-wal` next to your copy of `orders.db` and open it with
   SQLite so the WAL is replayed/checkpointed. Confirm `COUNT(*) FROM orders`
   equals `140`.

## Deliverables (under `/app/recovered/`)

- `/app/recovered/orders.db` — the recovered database with exactly `140` rows
  in the `orders` table. It must be readable with a SQLite client and pass
  `PRAGMA integrity_check`.
- `/app/recovered/report.json` — JSON report:
  ```json
  {"recovered": "<decimal value of the XOR byte you inferred>", "recovered_rows": 140}
  ```
  `recovered_rows` must be the integer 140.

## Verifier checks (independent — do not rely on passing them by reading this)

- `/app/evidence/` is unmodified: the verifier recomputes that
  `evidence/orders.db-wal` still has its exact original size and still decodes
  to the XORed (corrupt) state (i.e. its bytes at the frame headers cannot be
  valid WAL without applying a single-byte XOR).
- `/app/recovered/orders.db` exists, opens as a valid SQLite database, and
  `PRAGMA integrity_check` returns `ok`.
- `SELECT COUNT(*) FROM orders` == **140**.
- Spot rows are present: `id=1` patient `Ethan Coleman` status `done`;
  `id=101` patient `Marek Nowak` status `booked`; `id=140` patient
  `Sana Khalid` status `booked`.
- `/app/recovered/report.json` parses JSON with `recovered_rows == 140`.

Tools: the Python standard library (`sqlite3`, `json`) plus ordinary file
byte reads are enough. Write the bytewise XOR yourself. Work only on copies of
the evidence. Do not modify anything under `/app/evidence/`.