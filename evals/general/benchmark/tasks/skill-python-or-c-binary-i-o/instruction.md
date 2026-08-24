# Python/C-style binary I/O

`/app/numbers.bin` contains exactly 8 signed 32-bit integers encoded in native endianness? **No** — they are encoded in **little-endian** byte order (like a C `int32_t` array written to disk), consecutive with no padding.

Your task is to read this binary file using Python's standard binary I/O facilities (`struct` and/or `array`), compute the **sum** of the 8 integers, and write the result as a bare decimal integer (no trailing text) to `/app/sum.txt`.

Requirements:
- Use Python 3 (`bench-base:python-3.12` provides it). Write `/app/sum_bin.py` that performs the read, then run it so `/app/sum.txt` is produced.
- Read the raw bytes and interpret them as little-endian signed 32-bit integers (do NOT read the file as text).
- The known integer values sum to an exact integer; write just that integer.
- The output file must contain exactly one integer and nothing else (no spaces/newlines required, but a trailing newline is fine).
