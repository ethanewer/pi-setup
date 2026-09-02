# Linear cryptanalysis

**Linear cryptanalysis** studies linear approximations of a substitution box (S-box). For an S-box `S` over 3-bit inputs/outputs (values indexed by input `0..7`), a linear approximation is an *input mask* `a` and an *output mask* `b`. The approximation "holds" for an input `i` when the parity of `(i AND a)` equals the parity of `(S[i] AND b)`.

Parity means: the number of set bits, modulo 2.

The S-box used here is:

```
S = [6, 2, 5, 0, 3, 1, 7, 4]      # S[i] is the output for input i
```

Count, over all 8 inputs `i` in `0..7`, how many inputs satisfy

```
popcount(i & 5) % 2  ==  popcount(S[i] & 7) % 2
```

where `a = 5` (= 0b101) and `b = 7` (= 0b111).

You may write a short Python loop to count. The answer is **4** of the 8 inputs satisfy the linear approximation (verify by direct enumeration).

Write the count to `/app/answer.json`:

```json
{"count": 4}
```