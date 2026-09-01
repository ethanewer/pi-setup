# Log-concavity

A finite sequence of **non-negative** numbers `a[0], a[1], ..., a[n-1]` is **log-concave** when consecutive triples satisfy

```
a[k]^2 >= a[k-1] * a[k+1]      for every 1 <= k <= n-2
```

Equivalently, when all terms are strictly positive, the ratios `a[k+1]/a[k]` must be **non-increasing**.

Decide, for each array below, whether it is log-concave:

- `array1 = [2, 4, 8, 16, 32]` → ratios 2, 2, 2, 2 (non-increasing) → **true**
- `array2 = [1, 5, 6, 10]` → ratios 5, 1.2, 1.667 (the last ratio increases, violating the condition) → **false**

Check `array2` with the inequality directly:
- k=1: `5^2 = 25 >= 1*6 = 6` ok
- k=2: `6^2 = 36 >= 5*10 = 50` → **36 < 50, violates** → not log-concave.

Write the two decisions to `/app/answer.json`:

```json
{
  "array1_log_concave": true,
  "array2_log_concave": false
}
```