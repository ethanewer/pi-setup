`/app/archive.bin` is a single file that has been compressed with one common streaming compression format (gzip, bzip2, or lzma). The file's header can be used to identify which one.

Write a program `/app/extract.py` that:
1. opens `/app/archive.bin` in binary mode,
2. inspects the file header bytes to determine which compression format was used:
   - gzip files begin with the two bytes `\x1f\x8b`,
   - bzip2 files begin with the three bytes `BZh`,
   - lzma/XZ files begin with the magic bytes `\xfd` `7`, `z`, `X`, `Z`, `\x00`,
3. decompresses the entire file with the correct Python standard-library module (`gzip`, `bz2`, or `lzma`),
4. writes the decompressed bytes to `/app/extracted.txt`.

Run your program so `/app/extracted.txt` is produced. Do not hard-code the format; detect it from the header. The verifier reads `archive.bin`, identifies the format independently, decompresses it, and compares the result to `/app/extracted.txt`.