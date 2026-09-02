# SQLite page format

`/app/data.db` is a SQLite database file (created with the default 4096-byte page size, containing enough data to span many pages).

A SQLite **database file** starts with a 100-byte header, whose byte offsets are defined by the SQLite file format:

- bytes 0–15: the ASCII header string `SQLite format 3\0` (16 bytes). The `\0` terminator is at byte 15.
- bytes 16–17: the **page size**, stored as a big-endian 16-bit unsigned integer, 0x DC 00. A value of 1 at byte 16 means "65536".
- bytes 28–31: the **page count** (number of pages in the whole database file), stored as a big-endian 32-bit unsigned integer.

Your task: read the raw bytes of `/app/data.db` (as a binary file) and extract two header fields **directly from the bytes** — do not use any SQLite library for this.

Write a Python script `/app/pageinfo.py` that:

1. Opens `/app/data.db` in binary mode.
2. Reads bytes 16–17 and decodes the big-endian page size.
3. Reads bytes 28–31 and decodes the big-endian page count.
4. Writes `/app/header.txt` with exactly two lines:

```
page_size=<N>
page_count=<M>
```

(`<N>` is the page size, `<M>` is the page count — both plain integers.)

Then run `/app/pageinfo.py` so `/app/header.txt` exists.

The verifier reads the same two header fields directly from `/app/data.db` bytes and requires your file to match. It also sanity-checks that `page_count > 1` (the database is genuinely multi-page).