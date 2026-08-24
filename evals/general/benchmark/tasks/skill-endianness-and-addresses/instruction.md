# Binary fields, byte order, and a memory address

`/app/data.bin` is a 14-byte binary file with three numeric fields laid
out at these offsets:

| offset | size | type            | byte order  |
|-------:|-----:|-----------------|--------------|
| 0x00   | 4    | uint32          | little-endian |
| 0x04   | 2    | uint16          | big-endian   |
| 0x06   | 8    | uint64          | little-endian |

"Little-endian" stores the least-significant byte first (lowest
address); "big-endian" stores the most-significant byte first.

## Task

1. **Decode** the three fields above and write `/app/answer.txt` with one
   decimal integer per line, in the order of the table (`16909060`, `4386`,
   then the decoded `uint64`).

2. **Encode an address.** Take the 32-bit address `0xDEADBEEF` and write its
   4 bytes, in little-endian byte order, to `/app/out.bin` — so the resulting
   bytes are exactly `EF BE AD DE`.

The verifier re-decodes `/app/data.bin` itself, checks the three numbers
exactly, and checks that `/app/out.bin` is byte-for-byte
`b'\xef\xbe\xad\xde'`.

All values above are exact — do not add explanations, headers, or extra
lines to either output file.