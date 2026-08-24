# Differential cryptanalysis: output difference distribution of an S-box

Differential cryptanalysis studies how input differences propagate through
nonlinear components. For a substitution box (S-box), the differential
distribution for an input difference **Δa** counts, over all pairs
*(x, x ⊕ Δa)*, how often each **output difference** *S(x) ⊕ S(x ⊕ Δa)* occurs.

`/app/sbox.txt` contains a single line with 16 hex byte values, separated by
spaces — this is the S-box `S[0]..S[15]` (the first 16 entries of a standard
cipher S-box, given as a lookup table):

```
63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab 76
```

## Task

Write a Python 3 script `/app/differential.py` that:

1. Reads the 16 S-box entries from `/app/sbox.txt`.
2. Fixes the input difference **Δa = 1**.
3. For every input `x` in `0..15`, computes `y = x ^ 1` and
   `delta_out = S[x] ^ S[y]` (XOR).
4. Counts, for each output difference value `0..255`, how many of the 16
   pairs produced it.
5. Writes the results to `/app/differential.txt`:

   - 256 lines, line `i` (`i` = 0..255) has the format `i <count>` where
     `count` is how many of the 16 pairs gave output difference `i`.
   - A final line `best <value>` where `value` is the **largest** count on any
     output difference (the most likely output difference for Δa=1).

Example of the file shape (numbers shown are illustrative, not the answer):

```
0 0
1 0
...
best 4
```

All math is XOR on byte values `0..255` (the S-box entries are full bytes, so
output differences span the full byte range). The verifier recomputes the
exact distribution from `/app/sbox.txt` and compares line-by-line.