# FEAL-like round function

You are implementing the *round function* of a FEAL-like Feistel block cipher.

Define two byte primitives:

- `rot(x)`: rotate the byte `x` (integer 0..255) left by 2 bits, keeping it in
  the range 0..255: `rot(x) = ((x << 2) | (x >> 6)) & 0xFF`.
- `g(a, b)`: byte combine = `rot((a + b) & 0xFF)`.

The round function `fbox(R, K)` takes R and K — two 4-element lists of byte
values (integers 0..255) — and returns a 4-element list:

```
fbox(R, K)[i] = g(R[i], K[i])   for i in 0..3
```

Each output byte is `((R[i] + K[i]) & 0xFF)` rotated left by 2 bits.

## Your task

Write a Python 3 script `/app/fbox.py` that defines a top-level function
`fbox(r, k)` implementing the round function above exactly (the function must be
callable from outside; do not guard it behind `__name__ == '__main__'`).

Also read `/app/vectors.json` and write `/app/answers.json`:

- `/app/vectors.json` has the shape:
  ```json
  {"r": [18, 52, 86, 120], "k": [171, 205, 239, 1]}
  ```
- `/app/answers.json` must contain exactly
  ```json
  {"input": {"r": <same r>, "k": <same k>}, "output": [<computed fbox(r,k) bytes>]}
  ```

Then run the script so `/app/answers.json` exists. The verifier independently
computes `fbox` using the same formula and checks both `/app/answers.json` and
that `fbox` behaves correctly on extra fixed inputs (imported from your file).