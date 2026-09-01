# Quay NAS WAL de-obfuscation

The "Quay" NAS appliance was hit by a ransomware-lite prank: its SQLite
**write-ahead log** was scrambled with a single-byte XOR cipher and the
operator secrets that were committed but **never checkpointed** now live only
inside that scrambled log. The main database file `/app/quay.db` is intact.
You must reverse the transform, restore a valid WAL, and pull the secrets out
of it.

- Everything below (paths, magic constants, output formats) is **exact and
  authoritative**.
- **Do not modify** `/app/quay.db` or `/app/quay.db-wal.enc`.
- **Never read `/tests`** — it is not part of your workspace and is hidden.
- Caution: if you open a SQLite database in place and close it, SQLite may
  **checkpoint and delete** the adjacent `-wal` file. Never open the files in
  `/app` directly; work on copies (the tool below already does this for you
  in its `extract` subcommand).

## Deliverables (all required)

| Path | Meaning |
|------|---------|
| `/app/dewal.py` | your general recovery tool (run with `python3`), implementing both subcommands below — it must work on **any** XOR-obfuscated WAL, not just this one |
| `/app/quay.db-wal` | the restored, **valid** WAL for `/app/quay.db` (de-obfuscated from `/app/quay.db-wal.enc`) |
| `/app/secrets.json` | the secrets recovered from the restored WAL, in the JSON format below |

The evaluation re-runs `/app/dewal.py` on **hidden** obfuscated WALs (different
key bytes, different content), so the tool must be generic.

## Part 1 — reverse the single-byte XOR (`decode` subcommand)

`/app/quay.db-wal.enc` is a real SQLite WAL file whose **every byte** has been
XOR'd with a single unknown one-byte key `k`:

```
enc_byte = wal_byte ^ k        (same k for every byte of the file)
```

Every native SQLite WAL begins with a 4-byte magic: `37 7f 06 82` (big-endian
checksums) or `37 7f 06 83` (little-endian checksums). Because the key is a
single byte applied to every byte, XOR-ing the obfuscated first four bytes
with the correct `k` must reproduce one of those two magics — and **exactly
one** key in `0..255` does so.

- Implement:
  ```
  python3 /app/dewal.py decode <enc_wal_path> <out_wal_path>
  ```
  It finds the unique key, XOR-decodes **the whole file**, writes the valid
  WAL to `<out_wal_path>`, and prints one line `KEY=<k>` (decimal) to stdout.
- Run it on the provided input to produce **`/app/quay.db-wal`**:
  ```
  python3 /app/dewal.py decode /app/quay.db-wal.enc /app/quay.db-wal
  ```
  The result must be accepted by SQLite (see Part 2) — the restored file must
  be a real, usable WAL.

## Part 2 — extract the never-checkpointed secrets (`extract` subcommand)

Once a valid `quay.db-wal` sits next to a copy of `quay.db`, SQLite replays
the WAL on open and the `quay_secrets` table becomes readable. The table is:

```sql
CREATE TABLE quay_secrets(name TEXT PRIMARY KEY, value TEXT NOT NULL);
```

- Implement:
  ```
  python3 /app/dewal.py extract <db_path> <out_json>
  ```
  It reads the table `quay_secrets` from `<db_path>` (including rows that
  exist only in a companion `<db_path>-wal`, if present) and writes a JSON
  **object** mapping each `name` to its `value` to `<out_json>`, keys sorted.
  It must **not** checkpoint, modify or delete any file it reads: do the work
  on a temp copy, then discard it.
- Run it to produce **`/app/secrets.json`**:
  ```
  python3 /app/dewal.py extract /app/quay.db /app/secrets.json
  ```
  (Because `/app/quay.db-wal` now sits next to `/app/quay.db`, the extract
  picks up the never-checkpointed rows — without touching the files in
  `/app`, thanks to the temp-copy behavior.)

## Hidden evaluation

The verifier re-runs `/app/dewal.py` on at least two **hidden** cases:
- `decode` on a hidden XOR-obfuscated WAL with a **different key byte** and
  different content; the decoded output is byte-compared against the
  reference WAL, so the whole file must be decoded with the correct key.
- `extract` on a hidden database paired with its restored WAL; the JSON
  output must match the reference rows exactly.

A tool that hard-codes the key, the row values, or the file names will fail.
If all deliverables are correct and every check passes, the reward is 1.
