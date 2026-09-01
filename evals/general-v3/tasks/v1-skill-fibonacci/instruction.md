# Fibonacci

The Fibonacci sequence is defined as:

```
F(0) = 0
F(1) = 1
F(n) = F(n-1) + F(n-2)   for n >= 2
```

`/app/n.txt` contains a single integer `n` (here `n = 120`).

## Your task

Write a Python 3 script `/app/fib.py` that:

1. reads `/app/n.txt` to obtain `n`,
2. computes `F(n)` exactly (as an arbitrary-precision integer; do not use an
   approximate formula),
3. writes `/app/fib.json` containing exactly:
   ```json
   {"n": <int n>, "value": <int F(n)>}
   ```

Then run the script so the JSON exists. The verifier recomputes `F(n)` from the
same `n` independently and compares the exact integer value.