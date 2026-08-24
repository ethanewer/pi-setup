`/app/plex.txt` contains two complex numbers `a` and `b`, one per line, written as Python complex literals (for example `3+4j` and `1-2j`).

Write a program `/app/complex_ops.py` that:
1. reads the two lines from `/app/plex.txt`,
2. parses them into Python `complex` values,
3. computes:
   - `s = a + b`,
   - `p = a * b` (complex multiplication),
   - `ma = abs(a)` (magnitude of `a`),
   - `mb = abs(b)` (magnitude of `b`),
4. writes exactly four lines to `/app/results.txt`:

```
sum_real=<real part of s, 6 decimals>
sum_imag=<imag part of s, 6 decimals>
product_real=<real part of p, 6 decimals>
magnitude_a=<ma, 6 decimals>
magnitude_b=<mb, 6 decimals>
```

Use fixed 6-decimals formatting for every numeric value (e.g. `"{:.6f}".format(...)`). Run your program so `/app/results.txt` is produced. The verifier recomputes the same values independently and compares them (within a small tolerance).