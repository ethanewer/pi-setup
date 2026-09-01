`/app/data.bin` is a binary file with this exact record layout (little-endian throughout):
- bytes 0..3:   ASCII magic `DPAR`
- bytes 4..7:   unsigned 32-bit integer N = number of records
- then N records, each of 6 bytes:
  * unsigned 16-bit little-endian integer: record type
  * signed 32-bit little-endian integer: record value

Write a program `/app/parse_bin.py` that:
1. opens `/app/data.bin` in binary mode,
2. reads the header and unpacks each record using `struct` (or equivalent) and verifies the file length matches `N`,
3. computes:
   - `count` = N
   - `sum_type0` = sum of values of records whose type == 0
   - `sum_type1` = sum of values of records whose type == 1
   - `xor_all` = the bitwise XOR (integer) of all record values
4. writes `/app/parsed.json` with exactly those four integer fields.

Run your program so the JSON output exists with correct values. The verifier parses the same file independently.
