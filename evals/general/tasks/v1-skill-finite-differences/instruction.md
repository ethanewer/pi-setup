You are given a smooth function and need to estimate its derivative using **finite differences** (central scheme).

The function is `f(x) = x^3 - 2*x + 1`.

In `/app` there is `/app/xs.json` containing a JSON array of `x` values:
`[-2.0, -1.0, 0.0, 1.0, 2.0, 3.0]`

Use a central finite-difference approximation with step `h = 0.01`:
```
f'(x) = (f(x + h) - f(x - h)) / (2 * h)
```

Write `/app/diffs.json` — a JSON array of the derivatives at the **interior** points (all xs except the first and last), each rounded to 3 decimals:
```json
[-1.0, 2.0, ...]
```

Run your calculation so `/app/diffs.json` contains the correct values. Use `python3`.