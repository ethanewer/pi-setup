# Python C-style byte parsing (`struct`)

`/app/records.bin` contains a sequence of fixed-size binary records, each with the C struct layout:

- a 4-byte **unsigned integer** (little-endian) — a record id
- a 30-byte **fixed-length character string** (NUL-padded on the right)

Each record is exactly 34 bytes; the file contains 4 such records back to back, no padding between them.

Your task is to parse this binary file with Python's **`struct`** module (format `'<I30s'` for each record) and write to `/app/names.txt` the string from each record, one per line, **in file order**, with trailing NUL bytes stripped (trailing `\0` removed). Do not include the id. There must be no blank lines and no extra trailing whitespace beyond the newline that terminates each line.

Write the parser as `/app/parse_records.py` and run it so `/app/names.txt` is produced.
