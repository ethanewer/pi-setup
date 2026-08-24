# Item-061: Convert a hexadecimal number to decimal

`/app/input/hex.txt` contains a single hexadecimal (base-16) integer written in
uppercase, with **no** `0x` prefix and no trailing whitespace beyond the final
newline.

Write a Python program `/app/solve.py` (Python 3, standard library only) that:

1. Reads the hex string from `/app/input/hex.txt` and strips it.
2. Interprets it as a base-16 integer (digits `0-9` and `A-F`; both meanings of
   `A-F` are uppercase here).
3. Writes the decimal value (as a base-10 integer, no quotes, no trailing text)
   to `/app/answer.txt`.

Run it once so `/app/answer.txt` exists, e.g.:

```bash
python3 /app/solve.py
```

The verifier will independently convert the same hex string to decimal and
compare it with `/app/answer.txt`. Do not hard-code the answer — compute it
from the file contents.