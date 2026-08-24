# SQLite WAL file format

`/app/data.db-wal` is a **write-ahead log (WAL)** file for a SQLite database. WAL files are used when a database is opened in WAL journal mode. This particular file has been constructed to follow the SQLite WAL format exactly.

The SQLite WAL file layout:

- A 32-byte header:
  - bytes 0–3: the WAL **magic number** `0x377f0682` (as big-endian bytes `37 7f 06 82`).
  - bytes 4–7: the WAL **file format version**, a big-endian 32-bit integer (e.g. `3007000`).
  - bytes 8–11: the **page size**, a big-endian 32-bit integer.
  - bytes 12–15: the checkpoint sequence number.
  - bytes 16–19: salt-1; bytes 20–23: salt-2.
  - bytes 24–27: checksum-1; bytes 28–31: checksum-2.
- Then a sequence of 24-byte **frame headers**, each immediately followed by a page of database content. The first frame header starts at byte offset **32**:
  - bytes 0–3 of the frame (file bytes 32–35): the **page number** stored in this frame.
  - bytes 4–7 of the frame (file bytes 36–39): the **database size in pages after commit**.
  - bytes 8–23: salt-1, salt-2, checksum-1, checksum-2.

Your task: read the raw bytes of `/app/data.db-wal` and extract four fields **directly from the bytes** (binary `struct` unpacking; do not use any SQLite library).

Write a Python script `/app/walinfo.py` that:

1. Opens `/app/data.db-wal` in binary mode.
2. Decodes:
   - the magic number from bytes 0–3 (big-endian uint32),
   - the format version from bytes 4–7 (big-endian uint32),
   - the page size from bytes 8–11 (big-endian uint32),
   - the first frame's page number from bytes 32–35 (big-endian uint32),
   - the first frame's committed db size from bytes 36–39 (big-endian uint32).
3. Writes `/app/walinfo.txt` with exactly five lines:

```
magic=0x377f0682
version=3007000
page_size=4096
first_frame_page=3
first_frame_db_size=7
```

(The values read from the file must match these, since the file was authored to encode exactly them.)

Then run `/app/walinfo.py` so `/app/walinfo.txt` exists. The verifier unpacks the same five fields directly from the file and requires a match.