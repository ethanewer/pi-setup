# Incident: orders.db lost the recent appointments

The clinic's "orders" database (SQLite, WAL journal mode) lost the last batch
of appointments. This folder is a **read-only snapshot** taken by IT right
after the incident — treat every file here as original evidence.

## Layout

```
/app/evidence/
  orders.db        main database file (WAL mode)
  orders.db-wal    write-ahead log — THIS is the damaged file
  incident.md      this note
  audit.csv        last known-good export, taken the day before the incident
```

## What IT knows

- The exporter that wrote the `orders.db-wal` was recently modified. A code
  review found a bug in `wal_xor()`: it XORs the bytes it writes with a
  **single repeating byte** (one fixed key for the whole batch) — but only
  the frames it wrote, and the 32-byte WAL header was left intact.
- The exporter only touched the `-wal` file; `orders.db` itself was not
  modified.
- A `.db` copy from the day before shows `100` rows; the audit export from the
  same day also shows `100`. The last full inventory (a month ago) had `140`.

## Constraints from IT

- Do NOT modify anything under `/app/evidence/` (preserve the original
  evidence). Work on copies.
- If a copy of the database is opened while its `-wal` is present, SQLite may
  checkpoint/truncate the WAL on close — always copy the files first and work
  on the copies.
