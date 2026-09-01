# Fibonacci with modular arithmetic

This task exercises *fibonacci arithmetic*: computing Fibonacci values modulo a
prime for a very large index (so a naive per-term loop is infeasible — use the
**fast doubling** method, O(log n)).

Definitions (all values taken **modulo** `MOD = 1_000_000_007`, a prime):

```
F(0) = 0
F(1) = 1
F(n) = (F(n-1) + F(n-2)) % MOD

S(n) = (F(1) + F(2) + ... + F(n)) % MOD
```

The identity `S(n) = (F(n+2) - 1) % MOD` holds.

`/app/n.txt` contains `n = 1000000000000` (10^12).

## Your task

Write a Python 3 script `/app/fibmod.py` that:

1. reads `/app/n.txt`,
2. computes `F(n) % MOD` and `S(n) % MOD` efficiently using fast doubling
   (both must be integers in 0..MOD-1),
3. writes `/app/fib.json` containing exactly:
   ```json
   {"n": <int>, "mod": 1000000007, "F_n": <int F(n)%MOD>, "S_n": <int S(n)%MOD>}
   ```

Run the script so the JSON exists. The verifier recomputes F(n) and S(n) with an
independent fast-doubling implementation and compares the modular values.