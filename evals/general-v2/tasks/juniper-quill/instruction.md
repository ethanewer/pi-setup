# BrightShard recovery console

An ops post-incident console at **BrightShard** runs on a small appliance database.
An incident left the SQLite store at `/app/warehouse/` **partially damaged and
byte-transformed**. You must write a **single Python program** `/app/recover.py`
that detects the byte transform, reverses it, recovers as many intact rows as
possible, performs in-database cleaning, exports the recovered table as JSON and
as per-trial CSV files, keeps the database consistent with the exports, reclaims
the contents of a deleted-but-still-open file descriptor, and tunes the result so
a measured query meets a performance threshold.

The checker runs your program on the visible warehouse **and on fresh hidden
warehouses it supplies** (see CLI below), so it **must be written generally**, not
hard-coded to the shipped data.

## The damaged warehouse

`/app/warehouse/` contains:

- `inventory.db` — the (damaged) SQLite database. Byte-for-byte it has been run
  through a **4-byte repeating XOR transform**: every byte `i` of the file was
  xor-ed with `K[i mod 4]` for a fixed 4-byte key `K`. After reversing that
  transform the file is a normal, openable SQLite database (rollback-journal
  mode) that contains **all the intact rows** that survived the damage; rows that
  were corrupted beyond recovery are simply absent.
- `inventory.db-wal` — a write-ahead-log **witness**: it holds only a small
  (32-byte, header-only) WAL and is there purely so you can detect the transform.
  A genuine, untransformed SQLite WAL header always begins with the four bytes
  `37 7f 06 82`. Because the database itself is in rollback-journal mode, SQLite
  ignores this `-wal` when opening `inventory.db`; you use its header only to
  recover the key.

So the recovery recipe is:

1. Read the first four bytes of `inventory.db-wal`.
2. XOR them with `37 7f 06 82`, bytewise, to recover the key as
   `K[i] = wal_byte[i] ^ 0x37/0x7f/0x06/0x82`.
3. Reverse the transform over `inventory.db`: `original[i] = data[i] ^ K[i mod 4]`.
4. Open the untransformed database and read out every intact `customers` row.

> Cross-check (optional): an untransformed SQLite file also begins with the
> 16-byte string `SQLite format 3\0` starting at offset 0; the same `K` must
> reproduce it from the damaged `inventory.db` header. Every case uses the same
> mechanism; a case may use a key equal to `00 00 00 00` (no-op) or a key with
> all four bytes equal (a single-byte XOR) — both are still recovered by the same
> header-XOR arithmetic.

## Deliverables (the checker executes these)

1. `/app/recover.py` — the recovery program (you write it; executable, Python 3,
   standard library only: `sqlite3`, `json`, `csv`, `os`, ... are already
   available).
2. Emitted by running `/app/recover.py` (default target `/app`):
   - `/app/merged.json`
   - `/app/trial_1.csv` ... `/app/trial_20.csv` (this `trial_*.csv` family is
     declared as the deliverable `/app/trial_*.csv`)
   - `/app/warehouse/clean.db`
   - `/app/fd.txt`

## CLI contract

`python3 /app/recover.py [TARGET]`

- No argument → `TARGET = /app`.
- One argument → read `<TARGET>/warehouse/inventory.db` and
  `<TARGET>/warehouse/inventory.db-wal`, and write `<TARGET>/merged.json`,
  `<TARGET>/trial_1.csv` … `<TARGET>/trial_20.csv`,
  `<TARGET>/warehouse/clean.db`, and `<TARGET>/fd.txt`.
- The checker invokes the 1-argument form on fresh hidden workdirs and compares
  the written files; it also invokes the 0-argument form and checks `/app/...`.
- The program must exit cleanly (status 0) on both forms. It must **never read
  `/tests`, `/solution`, or the checker data**.

## The `customers` table (in the untransformed database)

Columns and SQL types:

| column  | type    | notes                                              |
|---------|---------|----------------------------------------------------|
| id      | INTEGER | the primary key for ordering/dedup                 |
| name    | TEXT    | text to be lowercased                              |
| email   | TEXT    | contact field 1 (may be empty `''` or `NULL`)      |
| phone   | TEXT    | contact field 2 (may be empty `''` or `NULL`)      |
| value   | TEXT    | non-empty digits-only string (e.g. `"007"`) |
| balance | INTEGER | an integer used only by the tuning/query step      |

A *contact field* is present if it is neither `NULL` nor the empty string.

The warehouse may also contain a large operational table named **`audit`**
(`id INTEGER, balance INTEGER`) — not a customer table; it exists so the query
tuning step has real data. Carry it into the clean database unchanged and index
it (see Tuning).

## Cleaning semantics (in this exact order)

1. **Recover** all intact `customers` rows from the untransformed database.
2. **Delete** every row that has **neither** contact field (both `email` and
   `phone` are empty/`NULL`).
3. **Normalize**: lower-case `name` (`str.lower()`; no trimming) and **cast
   `value` to an integer** (it is always digits-only; leading zeros are dropped
   by the cast, e.g. `"007"` → `7`). `balance` is already an integer.
4. **Remove duplicate ids.** Several recovered rows may share the same `id`.
   Keep exactly one record per `id`: the one whose tuple
   `(name, email, phone, value, balance)` is **smallest** when compared with
   `name`, `email`, `phone` as strings (empty string compares smallest) and
   `value`, `balance` as **integers**. (Because `value`/`balance` compare as
   integers, any two rows that tie on the tuple are the same normalized record,
   so there is never ambiguity.) Missing/NULL contact fields are treated as the
   empty string for this comparison.
5. **Sort** ascending by `id` (now unique).

The resulting set is the **cleaned recovered table**. Every export must contain
these rows and only these rows.

## Output formats

### `/app/merged.json`
A single JSON array of objects, one per cleaned record, sorted ascending by `id`,
**no duplicate ids**, containing exactly the three fields:
```json
[{"id": 2, "name": "greta lindqvist", "value": 4271139}, ...]
```
- `id`: integer; `name`: string (already lowercased); `value`: integer.
- Complete: the array has one element per cleaned record (nothing recovered is
  dropped).
- Ordering/duplicates/types are checked by distinct asserts.

### `/app/trial_1.csv` ... `/app/trial_20.csv`
Twenty comma-separated files, one per trial index. `trial_<N>.csv` for each
`N = 1..20`. Header line exactly:
```
id,name,email,phone,value,balance
```
then one row per cleaned record **in the same order as the final sorted table**
(ascending by `id`). `value` is the integer (e.g. `7`, not `"007"`). All twenty
files describe the **same** cleaned table.

### `/app/warehouse/clean.db`
A fresh SQLite database (write it as a **new** file; do **not** overwrite the
damaged input). It must contain:

- a `customers` table with columns `id, name, email, phone, value, balance`
  (same layout as the CSV header) whose rows are **exactly the cleaned table** —
  i.e. the database and the exported CSVs are **semantically identical**
  (same normalized rows; `value` stored as INTEGER).
- the `audit` table (if the source warehouse had one), contents carried over
  unchanged from the untransformed database.
- an index on `audit(balance)` so the tuning query is fast (see Tuning).

### `/app/fd.txt`
A small appliance process holds an open **file descriptor to an unlinked file**
and never exits. Recover that file's **content** (not merely a stale name) and
write it byte-for-byte to `/app/fd.txt`.

How to locate it: the keeper process records its PID in
`/tmp/juniper-lockbox/keeper.pid`. Its open descriptors appear under
`/proc/<pid>/fd/`; the one for a deleted file shows a target that ends with
`(deleted)`. Copy (or read) that descriptor's content to `/app/fd.txt`. The
content is the original CSV payload that was unlinked at appliance start. If you
cannot find it, the fd gate fails.

## Tuning: query-performance threshold

The checker **times a query** against your `/app/warehouse/clean.db` `audit`
table after warm-up:

```
SELECT COUNT(*) FROM audit WHERE balance BETWEEN 300000 AND 305000
```

It measures your timing against the **same query on an otherwise identical
database after creating an index on `audit(balance)`**, and the gate fails on any
correct-but-slow (unindexed full-scan) result. You must therefore make sure
`clean.db`'s `audit.balance` is **indexed** (e.g. `CREATE INDEX IF NOT EXISTS
idx_audit_balance ON audit(balance)`), that `audit` contains all the rows from
the source, and that the query returns the same result as on the source. A query
result mismatch, a missing/mismatched `audit` row count, or a timing above the
reference bound all fail distinct checks.

## Constraints

- Do NOT modify, rename, delete, or hard-code the files in `/app/warehouse`
  (write `clean.db` as a new file; never overwrite `inventory.db` or
  `inventory.db-wal`).
- Use only the Python 3 standard library (sqlite3 is bundled with Python).
- The program must never read `/tests`, `/solution`, or other checker data.
- Exit cleanly (status 0) on the 0- and 1-argument forms.

## Hints on what hidden cases probe

Hidden warehouses reuse the same contract with fresh data and **different keys**:
- a **zero key** (`00 00 00 00`, i.e. the header already shows the raw magic),
- a **single-byte key** (all four key bytes equal),
- a different 4-byte key.

They also vary: basket size (down to a small edge basket), **duplicate `id`
records** that must be deduped, rows **missing both contact fields** (to be
deleted), **email-only** and **phone-only** rows (kept), **uppercase** names
(lowered), and **leading-zero** digit values (cast to a plain integer). A
correct general solver reproduces the same cleaned table for every basket; a
solution overfit to the shipped warehouse (wrong key handling, wrong dedup
order, wrong drop rule, or a non-general recover.py) fails the hidden runs.
Hidden cases also re-check the database/CSV consistency and the JSON
ordering/dedup; the open-fd and performance gates are evaluated on the visible
`/app` warehouse.
