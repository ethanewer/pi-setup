# Brine Cipher tide-gauge WAL recovery

A tide-gauge appliance was shipped with its SQLite write-ahead log wrapped in a
thin encryption envelope. The gauge can no longer open its database: until the
WAL is restored, the newest tide readings exist nowhere else. You must invert
the envelope's single-byte transform, restore a **valid** WAL, and report the
peak reading. Everything below is exact:

- **Do not modify** `/app/gauge.db` or `/app/gauge.db-wal.enc`.
- **Never read `/tests`** — it is not part of your workspace and is hidden.

## The envelope format (`/app/gauge.db-wal.enc`)

```
offset 0  : 7 bytes  magic "ENCWAL1"
offset 7  : 1 byte   version (0x01)
offset 8  : 4 bytes  u32 LE payload_len
offset 12 : 4 bytes  u32 LE reserved (0x00000000)
offset 16 : payload_len bytes of the obfuscated WAL
```

Every payload byte was XOR'd with a single unknown one-byte key `k`:
`enc_byte = wal_byte ^ k`.

- A native SQLite WAL always begins with the big-endian magic `0x377F0682` or
  `0x377F0683` (bytes `37 7f 06 82` / `37 7f 06 83`). The first three bytes
  pin `k` uniquely: `k = enc[0]^0x37 = enc[1]^0x7f = enc[2]^0x06`, and the
  fourth decoded byte must land on `0x82` or `0x83`.
- Invert the transform over the **entire** payload to recover the original WAL.

## Deliverables (all three required)

| Path | Meaning |
|------|---------|
| `/app/dewal.py` | your reusable de-envelope tool (spec below) |
| `/app/gauge.db-wal` | the restored, **valid** WAL for `/app/gauge.db` |
| `/app/answer.txt` | the peak reading found after the WAL is restored (spec below) |

`/app/dewal.py` is invoked as:

```
python3 /app/dewal.py <enc_path> <out_wal_path>
```

It must:

1. Validate the envelope (magic, version, `payload_len` matching the remaining
   bytes).
2. Determine the single-byte XOR key `k` from the WAL magic bytes as above and
   decode the whole payload.
3. Write the decoded WAL bytes (and nothing else) to `<out_wal_path>`.
4. Print exactly one line to stdout: `KEY=<k>` with `k` in decimal.

It must work on **any** conforming envelope — different key byte, different
WAL content and length. The grader re-runs it on hidden envelopes.

## Reading the peak after restoration

`/app/gauge.db` (untouched) plus the restored `/app/gauge.db-wal` form a
working database whose table is:

```sql
CREATE TABLE gauge_readings(id INTEGER PRIMARY KEY, ts TEXT, level_mm INTEGER);
```

The latest committed rows live **only** in the WAL. To read them without
destroying your deliverable, copy `gauge.db` and your restored WAL into a
temporary directory as `g.db` / `g.db-wal` and open `g.db` with the `sqlite3`
module — SQLite will recover the committed frames from the copied WAL.

Then write `/app/answer.txt` with exactly one line:

```
max_level=<highest level_mm across all gauge_readings rows>
```

(the row values include those visible without the WAL; the true peak is only
reachable once the WAL is restored).

## Hidden evaluation

The verifier runs `python3 /app/dewal.py` unchanged on **hidden** envelopes
(different key, different content), checks the reported `KEY=`, and proves the
decoded output is a genuine WAL by pairing it with the case's database and
running SQLite `PRAGMA integrity_check` plus a row query.

## Constraints

- No network access; Python 3.12 standard library only.
- Do not modify `/app/gauge.db` or `/app/gauge.db-wal.enc`.
- If all checks pass, the reward is 1.
