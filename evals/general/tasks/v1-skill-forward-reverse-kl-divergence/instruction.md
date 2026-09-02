KL divergence is asymmetric between two reference distributions: the **forward** direction `KL(p || q)` and the **reverse** direction `KL(q || p)` are generally not equal.

In `/app`:
- `/app/p.json`: `[0.5, 0.3, 0.2]`
- `/app/q.json`: `[0.6, 0.25, 0.15]`

The formula is `KL(A || B) = sum_i A[i] * log( A[i] / B[i] )`. Use the **natural** log.

Write `/app/kl.py` that:
1. Computes `kl_fwd = KL(p || q)`.
2. Computes `kl_rev = KL(q || p)`.
3. Writes `/app/kl_divs.json` containing exactly:
```json
{"kl_fwd": <float rounded to 4 decimals>, "kl_rev": <float rounded to 4 decimals>}
```

Note: if any `A[i]` is 0 treat `A[i]*log(A[i]/B[i])` as 0. Run your script so `/app/kl_divs.json` contains the correct values. Use `python3` (the `math` module is standard).