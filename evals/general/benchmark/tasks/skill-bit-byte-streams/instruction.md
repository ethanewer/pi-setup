`/app/packed.bin` is a binary file in which a sequence of fixed-width unsigned integers has been packed at the *bit* level into bytes.

Packing scheme (the same scheme used to create the file):
- Each integer value is exactly 3 bits wide.
- Values are written back to back, most-significant bit first within each value.
- The resulting bit sequence is then divided into groups of 8 to form the bytes of the file, with each byte's most significant bit coming first in the bit stream. If the last byte is only partially filled, it is padded with zero bits at the low end.

The file is guaranteed to be an exact integer number of bytes and to contain an exact number of complete 3-bit values (no partial final value).

Write a program `/app/unpack.py` that:
1. opens `/app/packed.bin` in binary mode,
2. reads every bit in order (start with the most significant bit of the first byte),
3. consumes 3 bits at a time to reconstruct each unsigned integer value,
4. writes the resulting integer values, one per line, to `/app/decoded.txt`.

Run your program so the output file is produced. The verifier decodes the file independently with the same scheme and compares the value sequence.
