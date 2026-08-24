# Run-length encoding

`/app/input.txt` contains a single line of uppercase letters `A`–`Z` (no
spaces, no newlines inside the string; a trailing newline is present).

Write a Python 3 script `/app/rle.py` that reads `/app/input.txt`, computes
the **run-length encoding** of the string, and writes the encoded form to
`/app/encoded.txt`.

## Encoding rule

For every maximal run of identical adjacent characters, emit the single
character followed by the run length (as a decimal integer). Concatenate
these pairs with **no separators**.

Examples (each is an all-uppercase input and its encoding):

- `AAAABBBCC` -> `A4B3C2`
- `WWWWWWWW` -> `W8`
- `AB` -> `A1B1`
- `AAABBBCCDDDEEEEFFFFGGH` -> `A3B3C2D3E4F4G2H1`

Since every character is a letter and every count is a positive decimal
integer, the encoding is unambiguous: read one letter, then one or more
digits as the count.

Run the script so `/app/encoded.txt` exists and contains exactly the
run-length encoding of `/app/input.txt` (uppercase letters and digits only,
no trailing whitespace). The verifier recomputes the expected encoding from
`/app/input.txt` and compares it byte-for-byte.