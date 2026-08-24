`/app/numbers.txt` contains one non-negative integer per line. You must implement bitwise arithmetic over these integers using explicit bit manipulation (no string/builtin bit-count cheating).

Write a program `/app/bitwise.py` that:
1. reads all integers from `/app/numbers.txt`,
2. defines a function `popcount(n)` that counts the number of 1 bits in `n` using only bitwise operations (e.g. repeatedly clear the lowest set bit with `n &= n - 1`, or shift/mask), without relying on `bin(n).count` inside the function,
3. computes:
   - `sum_popcounts` = sum of `popcount(x)` over all numbers,
   - `and_all` = bitwise AND of all numbers (start from all the bits set, e.g. `~0`),
   - `xor_all` = bitwise XOR of all numbers,
4. writes `/app/bitwise.json` with exactly these three integer fields.

Run your program to produce the JSON. The verifier recomputes using equivalent arithmetic (including `bin(n).count('1')`, `&`, `^`) and compares.
